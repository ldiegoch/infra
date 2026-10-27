#!/usr/bin/env bash
# Orquestador de verificaciones locales (requisitos 5.1-5.5, 1.3, 1.4, 3.6, 9.5).
# Ejecuta, en orden, todas las verificaciones del contrato del diseño de
# base-y-ci, sin credenciales ni variables TF_VAR_*. Siempre corre todas.
#
# Salida:
#   ok   <nombre>                  por cada verificación que pasa
#   FALLA <nombre> + detalle       como máximo 40 líneas por falla
#   N verificaciones, M fallas     resumen final
# Código de salida: 0 si no hay fallas, 1 si las hay.
#
# Uso: ./scripts/check.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Evita artefactos de Python (__pycache__) en el repositorio.
export PYTHONDONTWRITEBYTECODE=1
export TF_IN_AUTOMATION=1

MAX_LINES=40
STACKS=(platform apps)
total=0
failures=0

# report <nombre> <código> <salida>
report() {
  local name="$1" code="$2" out="$3"
  total=$((total + 1))
  if [[ "$code" -eq 0 ]]; then
    echo "ok   $name"
    return
  fi
  failures=$((failures + 1))
  echo "FALLA $name"
  [[ -z "$out" ]] && out="(sin salida; código $code)"
  local n
  n="$(printf '%s\n' "$out" | wc -l)"
  printf '%s\n' "$out" | head -n "$MAX_LINES" | sed 's/^/  /'
  if ((n > MAX_LINES)); then
    echo "  ... ($((n - MAX_LINES)) líneas más omitidas)"
  fi
}

# run <nombre> <comando...>: ejecuta el comando y reporta su resultado.
run() {
  local name="$1" out code
  shift
  out="$("$@" 2>&1)"
  code=$?
  report "$name" "$code" "$out"
}

# need <herramienta...>: imprime "falta <herramienta>" por cada ausente.
need() {
  local tool rc=0
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "falta $tool"
      rc=1
    fi
  done
  return "$rc"
}

# Directorios de módulos (modules/*/ con archivos .tf).
module_dirs() {
  local d
  for d in modules/*/; do
    [[ -d "$d" ]] || continue
    compgen -G "${d}*.tf" >/dev/null && echo "${d%/}"
  done
}

# --- 1. Herramientas -------------------------------------------------------
check_tools() {
  local rc=0
  need tofu tflint trivy gitleaks python3 jq || rc=1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import yaml' >/dev/null 2>&1 || { echo "falta python3-yaml (módulo yaml)"; rc=1; }
    python3 -c 'import jsonschema' >/dev/null 2>&1 || { echo "falta python3-jsonschema (módulo jsonschema)"; rc=1; }
  fi
  return "$rc"
}

# --- 2. Formato ------------------------------------------------------------
check_fmt() {
  need tofu || return 1
  tofu fmt -check -recursive -no-color
}

# --- 3. Validación de stacks y módulos -------------------------------------
check_validate() {
  local dir="$1"
  need tofu || return 1
  tofu -chdir="$dir" init -backend=false -input=false -no-color >/dev/null 2>"$TMP/init.err" || {
    echo "tofu init -backend=false falló en $dir:"
    cat "$TMP/init.err"
    return 1
  }
  tofu -chdir="$dir" validate -no-color
}

# --- 4. Lock file condicional ----------------------------------------------
# Solo los stacks que declaran required_providers deben versionar su lock file.
check_lockfile() {
  local dir rc=0 with_providers=0
  for dir in "${STACKS[@]}"; do
    grep -qs 'required_providers' "$dir"/*.tf || continue
    with_providers=1
    if ! git ls-files --error-unmatch "$dir/.terraform.lock.hcl" >/dev/null 2>&1; then
      echo "falta $dir/.terraform.lock.hcl en Git: ejecuta tofu init en $dir y versiona el archivo"
      rc=1
    fi
  done
  ((with_providers)) || echo "ningún stack declara required_providers"
  return "$rc"
}

# --- 5. Pruebas de OpenTofu ------------------------------------------------
# Devuelve los directorios (stacks y módulos) con tests/*.tftest.hcl.
tofu_test_dirs() {
  local d
  for d in "${STACKS[@]}" $(module_dirs); do
    compgen -G "$d/tests/*.tftest.hcl" >/dev/null && echo "$d"
  done
}

check_tofu_test() {
  local dir="$1"
  need tofu || return 1
  tofu -chdir="$dir" test -no-color
}

# --- 6. Pruebas de scripts -------------------------------------------------
check_py_test() {
  local file="$1"
  need python3 || return 1
  python3 -B -m unittest discover -s scripts/tests -t scripts/tests -p "$(basename "$file")"
}

check_sh_test() {
  bash "$1"
}

# --- 7. Linter -------------------------------------------------------------
check_tflint() {
  need tflint || return 1
  tflint --recursive --config "$ROOT/.tflint.hcl" --no-color
}

# --- 8. Escaneo de IaC -----------------------------------------------------
check_trivy() {
  need trivy || return 1
  trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 .
}

# --- 9. Detección de secretos ----------------------------------------------
check_gitleaks() {
  need gitleaks || return 1
  gitleaks git --redact --no-banner --no-color --log-level error .
}

# --- 10 y 11. Cifrado y catálogo -------------------------------------------
check_py_script() {
  need python3 || return 1
  python3 -B "$1"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run "herramientas" check_tools
run "formato (tofu fmt)" check_fmt

for dir in "${STACKS[@]}" $(module_dirs); do
  run "validación $dir" check_validate "$dir"
done

run "lock file de providers" check_lockfile

mapfile -t test_dirs < <(tofu_test_dirs)
if ((${#test_dirs[@]} == 0)); then
  report "tofu test: omitido, no hay tests/*.tftest.hcl" 0 ""
else
  for dir in "${test_dirs[@]}"; do
    run "tofu test $dir" check_tofu_test "$dir"
  done
fi

# Descubrimiento por patrón: las pruebas nuevas entran sin editar este archivo.
for file in scripts/tests/test_*.py; do
  [[ -f "$file" ]] && run "prueba $file" check_py_test "$file"
done
for file in scripts/tests/test_*.sh; do
  [[ -f "$file" ]] && run "prueba $file" check_sh_test "$file"
done

run "linter (tflint)" check_tflint
run "escaneo de IaC (trivy config)" check_trivy
run "detección de secretos (gitleaks)" check_gitleaks
run "cifrado del catálogo (check_sops.py)" check_py_script scripts/check_sops.py
run "catálogo (check_catalog.py)" check_py_script scripts/check_catalog.py

echo "$total verificaciones, $failures fallas"
((failures == 0))
