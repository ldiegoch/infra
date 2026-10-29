# 0012. Validador de `app.yaml` con `python3-jsonschema`

- Estado: aceptado
- Fecha: 2026-10-27

## Contexto
Cada `app.yaml` debe validarse contra un esquema en pre-commit, en `scripts/check.sh` y en el CI. El dev container no tiene un validador de JSON Schema.

## Decisión
Instalar `python3-jsonschema` y, de forma explícita, `python3-yaml` desde apt en `.devcontainer/Dockerfile`. `scripts/check_catalog.py` valida contra `schema/app.schema.json` y revisa las reglas que JSON Schema no expresa (nombre igual a la carpeta).

## Alternativas consideradas
- `check-jsonschema` desde PyPI o pre-commit: otra descarga y otra versión que fijar.
- `ajv` con Node: un paquete npm y un `package.json` en el repo.
- Validar con bloques `check`/`validation` de OpenTofu en `apps/`: no corre en pre-commit y duplica el esquema.

## Consecuencias
No agrega gestores de paquetes: la versión queda fijada por la imagen base Ubuntu 24.04 (`python3-jsonschema` 4.10.3, que soporta Draft 2020-12). `python3-yaml` hoy llega solo como dependencia de pre-commit; ahora se declara. Hay que reconstruir el dev container. Por el principio 8 de la constitución, el paquete se agrega solo cuando el humano acepte este ADR.
