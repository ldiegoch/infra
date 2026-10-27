#!/usr/bin/env bash
# Pruebas de scripts/destroy-guard.sh con planes de ejemplo (requisitos 8.1-8.5).
# Sin red ni credenciales: solo bash, jq y los fixtures de fixtures/plans/.
# Uso: bash scripts/tests/test_destroy_guard.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../destroy-guard.sh"
PLANS="$HERE/fixtures/plans"

passed=0
failed=0
out=""
code=0

# run_guard <valor ALLOW_DESTROY | -unset> <plan>
run_guard() {
  local allow="$1" plan="$2"
  if [[ "$allow" == "-unset" ]]; then
    out="$(env -u ALLOW_DESTROY bash "$GUARD" "$plan" 2>&1)"
  else
    out="$(ALLOW_DESTROY="$allow" bash "$GUARD" "$plan" 2>&1)"
  fi
  code=$?
}

fail() {
  echo "FALLA: $1"
  echo "  código: $code"
  echo "$out" | sed 's/^/  | /'
  failed=$((failed + 1))
}

ok() {
  echo "ok: $1"
  passed=$((passed + 1))
}

expect_code() { [[ "$code" -eq "$1" ]]; }
has_line() { grep -qxF -- "$1" <<<"$out"; }
lacks() { ! grep -qF -- "$1" <<<"$out"; }
last_line() { tail -n 1 <<<"$out"; }
no_values() { lacks "fake-attribute-value"; }

# 8.1: solo creación y actualización.
name="8.1 solo creación se aprueba"
run_guard false "$PLANS/create-only.json"
if expect_code 0 && [[ "$(last_line)" == "APROBADO" ]] \
  && lacks "digitalocean_droplet.host" && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.1: reemplazo y borrado de contenedores.
name="8.1 reemplazo de docker_container se aprueba y se lista"
run_guard false "$PLANS/container-replace.json"
if expect_code 0 && [[ "$(last_line)" == "APROBADO" ]] \
  && has_line "replace docker_container.web (docker_container)" \
  && has_line "delete docker_container.worker (docker_container)" \
  && lacks "cloudflare_dns_record" && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.2: borrado de servidor sin la etiqueta.
name="8.2 delete de digitalocean_droplet con false se rechaza con la lista"
run_guard false "$PLANS/server-delete.json"
if expect_code 1 && has_line "delete digitalocean_droplet.host (digitalocean_droplet)" \
  && [[ "$(last_line)" == RECHAZADO:* ]] && lacks "docker_container.web" && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.3: con la etiqueta allow-destroy.
name="8.3 delete de digitalocean_droplet con true se aprueba con la lista"
run_guard true "$PLANS/server-delete.json"
if expect_code 0 && has_line "delete digitalocean_droplet.host (digitalocean_droplet)" \
  && [[ "$(last_line)" == "APROBADO" ]] && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.5: PR fusionado indeterminado (unknown) con reemplazo create-before-destroy.
name="8.5 [\"create\",\"delete\"] de recurso no contenedor con unknown se rechaza"
run_guard unknown "$PLANS/create-before-destroy.json"
if expect_code 1 \
  && has_line 'replace cloudflare_dns_record.app["web"] (cloudflare_dns_record)' \
  && [[ "$(last_line)" == RECHAZADO:* ]] && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.5: forget de un recurso no contenedor con unknown.
name="8.5 forget de recurso no contenedor con unknown se rechaza"
run_guard unknown "$PLANS/forget.json"
if expect_code 1 && has_line "forget neon_database.app (neon_database)" \
  && [[ "$(last_line)" == RECHAZADO:* ]] && no_values; then
  ok "$name"
else fail "$name"; fi

# 8.5: forget con la etiqueta se aprueba (misma regla que delete).
name="8.3 forget con true se aprueba con la lista"
run_guard true "$PLANS/forget.json"
if expect_code 0 && has_line "forget neon_database.app (neon_database)" \
  && [[ "$(last_line)" == "APROBADO" ]]; then
  ok "$name"
else fail "$name"; fi

# 8.5: plan ilegible, aun con la etiqueta.
name="8.5 JSON inválido se rechaza con código 2"
run_guard true "$PLANS/invalid.json"
if expect_code 2 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

name="8.5 resource_changes con forma inválida se rechaza con código 2"
run_guard true "$PLANS/bad-structure.json"
if expect_code 2 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

name="8.5 plan inexistente se rechaza con código 2"
run_guard true "$PLANS/no-existe.json"
if expect_code 2 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

name="8.5 archivo vacío se rechaza con código 2"
empty="$(mktemp)"
run_guard true "$empty"
rm -f "$empty"
if expect_code 2 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

name="8.5 sin argumento se rechaza con código 2"
out="$(ALLOW_DESTROY=true bash "$GUARD" 2>&1)"
code=$?
if expect_code 2 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

# Valores de autorización desconocidos se tratan como unknown.
for value in yes TRUE 1 ""; do
  name="valor de etiqueta desconocido ('$value') se trata como unknown"
  run_guard "$value" "$PLANS/server-delete.json"
  if expect_code 1 && [[ "$(last_line)" == RECHAZADO:* ]]; then
    ok "$name"
  else fail "$name"; fi
done

name="ALLOW_DESTROY sin definir se trata como unknown"
run_guard -unset "$PLANS/server-delete.json"
if expect_code 1 && [[ "$(last_line)" == RECHAZADO:* ]]; then
  ok "$name"
else fail "$name"; fi

# Sin recursos marcados, la etiqueta indeterminada no bloquea.
name="8.1 solo creación con unknown se aprueba"
run_guard unknown "$PLANS/create-only.json"
if expect_code 0 && [[ "$(last_line)" == "APROBADO" ]]; then
  ok "$name"
else fail "$name"; fi

name="plan sin cambios (sin resource_changes) se aprueba"
run_guard unknown "$PLANS/no-changes.json"
if expect_code 0 && [[ "$(last_line)" == "APROBADO" ]]; then
  ok "$name"
else fail "$name"; fi

echo "resultado: $passed pasaron, $failed fallaron"
[[ "$failed" -eq 0 ]]
