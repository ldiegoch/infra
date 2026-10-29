#!/usr/bin/env bash
# Guardia contra destrucciones: decide si un plan de OpenTofu puede aplicarse.
#
# Uso: ALLOW_DESTROY=true|false|unknown destroy-guard.sh <plan.json>
#
# Lee la salida de `tofu show -json` y consume solo
# resource_changes[].{address,type,change.actions}. Un recurso queda marcado
# si sus acciones incluyen "delete" o "forget" y su tipo no es un contenedor
# (docker_container). ALLOW_DESTROY lo resuelve quien invoca la guardia a
# partir de la etiqueta allow-destroy; cualquier otro valor cuenta como
# "unknown". Es pura: no usa la red ni imprime valores de atributos.
#
# Salida: una línea "<acción> <address> (<type>)" por recurso marcado o
# contenedor afectado y un veredicto final "APROBADO" o "RECHAZADO: <motivo>".
# Códigos: 0 aprobado, 1 rechazado por destrucciones sin autorización,
# 2 plan ilegible o con forma inválida (fallo cerrado).
set -euo pipefail

ALLOWED_TYPES='["docker_container"]'

reject_unreadable() {
  echo "RECHAZADO: no se pudo leer el plan ($1)"
  exit 2
}

if [[ $# -ne 1 || -z "$1" ]]; then
  reject_unreadable "uso: destroy-guard.sh <plan.json>"
fi
plan="$1"
if [[ ! -f "$plan" || ! -r "$plan" ]]; then
  reject_unreadable "no existe o no es legible: $plan"
fi

case "${ALLOW_DESTROY:-unknown}" in
  true | false) allow="$ALLOW_DESTROY" ;;
  *) allow="unknown" ;;
esac

# Valida la forma y emite una fila TSV por recurso con delete o forget:
# <flagged|allowed> <acción> <address> <type>
# shellcheck disable=SC2016  # el filtro es jq, no expansión de bash
filter='
  def valid_change:
    type == "object"
    and (.address | type) == "string"
    and (.type | type) == "string"
    and (.change | type) == "object"
    and (.change.actions | type) == "array"
    and all(.change.actions[]; type == "string");
  def action_name:
    if (index("delete") != null) and (index("create") != null) then "replace"
    else join("+") end;
  [inputs]
  | if length != 1 then error("se esperaba un documento JSON") else .[0] end
  | if type != "object" then error("no es un objeto")
    elif has("resource_changes") then
      if (.resource_changes | type) == "array"
         and all(.resource_changes[]; valid_change)
      then .resource_changes
      else error("resource_changes inválido") end
    elif (.format_version | type) == "string" then []
    else error("no es un plan") end
  | .[]
  | select(.change.actions | any(. == "delete" or . == "forget"))
  | [ (if (.type | IN($allowed[])) then "allowed" else "flagged" end),
      (.change.actions | action_name), .address, .type ]
  | @tsv
'

if ! rows="$(jq -r -n --argjson allowed "$ALLOWED_TYPES" "$filter" "$plan" 2>/dev/null)"; then
  reject_unreadable "JSON inválido o sin resource_changes válido: $plan"
fi

flagged=0
while IFS=$'\t' read -r kind action address rtype; do
  [[ -z "$kind" ]] && continue
  echo "$action $address ($rtype)"
  if [[ "$kind" == "flagged" ]]; then
    flagged=$((flagged + 1))
  fi
done <<<"$rows"

if [[ "$flagged" -eq 0 ]]; then
  echo "APROBADO"
  exit 0
fi

case "$allow" in
  true)
    echo "APROBADO"
    exit 0
    ;;
  false)
    echo "RECHAZADO: $flagged recurso(s) distinto(s) de un contenedor se destruyen, reemplazan u olvidan sin la etiqueta allow-destroy"
    exit 1
    ;;
  *)
    echo "RECHAZADO: $flagged recurso(s) distinto(s) de un contenedor se destruyen, reemplazan u olvidan y no se pudo determinar la etiqueta allow-destroy"
    exit 1
    ;;
esac
