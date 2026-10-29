#!/usr/bin/env python3
"""Verifica que catalog/<app>/secrets.enc.yaml esté cifrado para los destinatarios de .sops.yaml.

Uso: check_sops.py [--config ARCHIVO] [--catalog DIR] [secrets.enc.yaml ...]

Sin rutas revisa <catalog>/*/secrets.enc.yaml, incluidas las carpetas que
empiezan con "_" (la excepción de las plantillas es solo para app.yaml). Solo lee metadatos: nunca descifra, nunca invoca herramientas
externas ni usa llaves privadas. Imprime "<ruta>: <motivo>" por archivo
inválido, nunca un valor.
Códigos: 0 todo cifrado, 1 hay archivos inválidos, 2 .sops.yaml falta o es inválido.
"""

import argparse
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = ROOT / ".sops.yaml"
DEFAULT_CATALOG = ROOT / "catalog"
PRIVATE_KEY_MARKER = "AGE-SECRET-KEY-"


class ConfigError(Exception):
    """.sops.yaml falta o no tiene la forma esperada."""


def load_rules(config_path):
    """Devuelve [(regex compilada, {destinatarios age})] de las creation_rules."""
    try:
        text = config_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ConfigError(f"no se puede leer ({type(exc).__name__})") from None
    if PRIVATE_KEY_MARKER in text.upper():
        raise ConfigError("contiene una llave privada; solo se permiten llaves públicas")
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError:
        raise ConfigError("YAML inválido") from None
    rules = data.get("creation_rules") if isinstance(data, dict) else None
    if not isinstance(rules, list) or not rules:
        raise ConfigError("falta la lista creation_rules")

    parsed = []
    for index, rule in enumerate(rules):
        where = f"creation_rules[{index}]"
        if not isinstance(rule, dict):
            raise ConfigError(f"{where} debe ser un mapa")
        pattern, age = rule.get("path_regex"), rule.get("age")
        if not isinstance(pattern, str) or not pattern:
            raise ConfigError(f"{where} no tiene path_regex")
        try:
            regex = re.compile(pattern)
        except re.error:
            raise ConfigError(f"{where}: path_regex no es una expresión regular válida") from None
        if not isinstance(age, str) or not age.strip():
            raise ConfigError(f"{where} no tiene destinatarios age")
        recipients = {key.strip() for key in age.split(",") if key.strip()}
        if not all(key.startswith("age1") for key in recipients):
            raise ConfigError(f"{where}: cada destinatario age debe empezar con age1")
        parsed.append((regex, recipients))
    return parsed


def relative_key(path, bases):
    """Ruta relativa (posix) a la primera base que la contenga; si no, la ruta tal cual."""
    resolved = path.resolve()
    for base in bases:
        try:
            return resolved.relative_to(base.resolve()).as_posix()
        except ValueError:
            continue
    return path.as_posix()


def plaintext_leaves(node, prefix=""):
    """Rutas de claves cuyo valor hoja no empieza con ENC[ (sin devolver valores)."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from plaintext_leaves(value, f"{prefix}.{key}" if prefix else str(key))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from plaintext_leaves(value, f"{prefix}[{index}]")
    elif not (isinstance(node, str) and node.startswith("ENC[")):
        yield prefix or "(raíz)"


def check_file(path, key, rules):
    """Devuelve los motivos por los que un secrets.enc.yaml es inválido."""
    expected = next((recipients for regex, recipients in rules if regex.search(key)), None)
    if expected is None:
        return ["ninguna regla de .sops.yaml aplica a esta ruta"]
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError) as exc:
        return [f"no se puede leer ({type(exc).__name__})"]
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        return [f"YAML inválido{f' en la línea {mark.line + 1}' if mark else ''}"]

    if not isinstance(data, dict) or not isinstance(data.get("sops"), dict):
        return ["sin metadatos de cifrado (falta el mapa sops); cifra el archivo con la regla de .sops.yaml"]
    meta = data["sops"]
    reasons = []
    if not meta.get("mac"):
        reasons.append("metadatos de cifrado incompletos: falta sops.mac")
    entries = meta.get("age")
    if not isinstance(entries, list) or not entries:
        reasons.append("metadatos de cifrado incompletos: falta la lista sops.age")
    else:
        actual = {e.get("recipient") for e in entries if isinstance(e, dict) and isinstance(e.get("recipient"), str)}
        if actual != expected:
            detail = []
            missing, extra = sorted(expected - actual), sorted(actual - expected)
            if missing:
                detail.append(f"faltan {', '.join(missing)}")
            if extra:
                detail.append(f"sobran {', '.join(extra)}")
            reasons.append(f"destinatarios distintos de .sops.yaml ({'; '.join(detail)})")
    content = {k: v for k, v in data.items() if k != "sops"}
    reasons.extend(f"valor sin cifrar en {leaf}" for leaf in plaintext_leaves(content))
    return reasons


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args(argv)

    try:
        rules = load_rules(args.config)
    except ConfigError as exc:
        print(f"{args.config}: .sops.yaml inválido: {exc}")
        return 2

    paths = args.paths or sorted(args.catalog.glob("*/secrets.enc.yaml"))
    bases = [args.catalog.parent, args.config.parent]
    lines = []
    for path in paths:
        key = relative_key(path, bases)
        lines.extend(f"{key}: {reason}" for reason in check_file(path, key, rules))
    for line in lines:
        print(line)
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main())
