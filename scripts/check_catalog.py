#!/usr/bin/env python3
"""Valida catalog/<app>/app.yaml contra schema/app.schema.json.

Uso: check_catalog.py [--catalog DIR] [--schema ARCHIVO] [app.yaml ...]

Sin rutas revisa <catalog>/*/app.yaml. Ignora las carpetas que empiezan con
"_". Imprime "<app>: <campo>: <motivo>" por error, nunca el valor.
Códigos: 0 sin errores, 1 hay app.yaml inválidos, 2 el esquema no carga.
"""

import argparse
import json
import sys
from pathlib import Path

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "catalog"
DEFAULT_SCHEMA = ROOT / "schema" / "app.schema.json"

PATTERN_REASONS = {
    "^[a-z0-9]+(-[a-z0-9]+)*$": "debe estar en kebab-case",
    "^[A-Za-z_][A-Za-z0-9_]*$": "debe ser un nombre de variable (letras, números y _), sin valores",
    "^[^@\\s:]+(:[^@\\s]+)?@sha256:[a-f0-9]{64}$": "la imagen debe fijarse por digest (@sha256:<64 hex>)",
    "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$": "debe ser un FQDN en minúsculas, sin comodines",
    "^/": "debe empezar con /",
}


def reason(error):
    """Motivo legible del error, sin incluir el valor de la instancia."""
    text = describe(error)
    return f"una clave {text}" if "propertyNames" in error.schema_path else text


def describe(error):
    kind, rule = error.validator, error.validator_value
    if kind is None:  # esquema false: hostname en un servicio privado
        return "solo se permite con public: true"
    if kind == "const" and error.absolute_path and error.absolute_path[-1] == "uses_database":
        return "uses_database: true requiere database.neon: true"
    if kind == "pattern":
        return PATTERN_REASONS.get(rule, f"no cumple el patrón {rule}")
    if kind == "required":
        missing = [name for name in rule if name not in error.instance]
        return f"falta el campo requerido {', '.join(missing)}"
    if kind == "additionalProperties":
        allowed = error.schema.get("properties", {})
        extra = sorted(str(key) for key in error.instance if key not in allowed)
        return f"campo no permitido: {', '.join(extra)}"
    if kind == "type":
        return f"debe ser de tipo {rule}"
    if kind == "minimum":
        return f"debe ser mayor o igual a {rule}"
    if kind == "maximum":
        return f"debe ser menor o igual a {rule}"
    if kind == "minProperties":
        return f"debe tener al menos {rule} entrada(s)"
    if kind == "maxLength":
        return f"debe tener como máximo {rule} caracteres"
    if kind == "uniqueItems":
        return "tiene elementos repetidos"
    return f"no cumple la regla {kind}"


def field(path):
    return ".".join(str(part) for part in path) or "(raíz)"


def check_app(path, validator):
    """Devuelve las líneas de error de un app.yaml."""
    app = path.parent.name
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError:
        return [f"{app}: (archivo): no se puede leer {path}"]
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        where = f" en la línea {mark.line + 1}" if mark else ""
        return [f"{app}: (archivo): YAML inválido{where}"]

    errors = sorted(validator.iter_errors(data), key=lambda e: [str(p) for p in e.absolute_path])
    lines = [f"{app}: {field(e.absolute_path)}: {reason(e)}" for e in errors]
    if isinstance(data, dict) and isinstance(data.get("name"), str) and data["name"] != app:
        lines.append(f"{app}: name: debe coincidir con el nombre de la carpeta")
    return list(dict.fromkeys(lines))


def load_validator(schema_path):
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    return jsonschema.Draft202012Validator(schema)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args(argv)

    try:
        validator = load_validator(args.schema)
    except (OSError, ValueError, jsonschema.SchemaError) as exc:
        print(f"{args.schema}: el esquema no carga: {type(exc).__name__}")
        return 2

    paths = args.paths or sorted(args.catalog.glob("*/app.yaml"))
    lines = []
    for path in paths:
        if not path.parent.name.startswith("_"):
            lines.extend(check_app(path, validator))
    for line in lines:
        print(line)
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main())
