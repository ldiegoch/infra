#!/usr/bin/env bash
# Publica el plan de un stack como un único comentario en el PR (requisitos
# 6.2 y 6.3): busca el comentario del bot que empieza con el marcador
# `<!-- tofu-plan:<stack> -->` y lo reemplaza; si no existe, lo crea.
#
# Uso: pr-comment.sh <stack> <plan.txt> <salida-de-la-guardia>
#   stack                 platform | apps
#   plan.txt              salida de `tofu show -no-color tfplan` (ya enmascarada)
#   salida-de-la-guardia  archivo con la salida de scripts/destroy-guard.sh
# Entorno: GH_TOKEN, PR_NUMBER y GITHUB_REPOSITORY (owner/repo).
#   PR_COMMENT_AUTHOR (opcional): autor de los comentarios a reemplazar;
#   por omisión github-actions[bot].
#
# Nunca publica el plan JSON ni variables de entorno: solo los dos archivos
# de texto. El plan se trunca a MAX_PLAN_CHARS y la guardia a
# MAX_GUARD_CHARS, cada uno con su aviso, para no superar el límite de
# 65 536 caracteres de un comentario de GitHub.
# Códigos: 0 publicado, 1 error de gh, 2 uso o entorno inválido.
set -euo pipefail

MAX_PLAN_CHARS=60000
MAX_GUARD_CHARS=4000

die() {
  echo "pr-comment: $1" >&2
  exit 2
}

[[ $# -eq 3 ]] || die "uso: pr-comment.sh <platform|apps> <plan.txt> <salida-de-la-guardia>"
stack="$1"
plan_file="$2"
guard_file="$3"

case "$stack" in
  platform | apps) ;;
  *) die "stack desconocido: $stack (se espera platform o apps)" ;;
esac
[[ -f "$plan_file" && -r "$plan_file" ]] || die "no se puede leer el plan: $plan_file"
[[ -f "$guard_file" && -r "$guard_file" ]] || die "no se puede leer la salida de la guardia: $guard_file"

for var in GH_TOKEN PR_NUMBER GITHUB_REPOSITORY; do
  [[ -n "${!var:-}" ]] || die "falta la variable de entorno $var"
done
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || die "PR_NUMBER debe ser un número"
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || die "GITHUB_REPOSITORY debe tener la forma owner/repo"
author="${PR_COMMENT_AUTHOR:-github-actions[bot]}"
# Se inserta en la expresión --jq (gh no admite --arg): solo caracteres seguros.
[[ "$author" =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] \
  || die "PR_COMMENT_AUTHOR debe ser un login de GitHub (opcionalmente con [bot])"

command -v gh >/dev/null || die "falta gh"
command -v jq >/dev/null || die "falta jq"

marker="<!-- tofu-plan:${stack} -->"

# Contar caracteres y no bytes cuando hay una configuración regional UTF-8.
if locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then
  export LC_ALL=C.UTF-8
fi

# fence <texto>: cerco de comillas invertidas más largo que la racha más
# larga dentro del texto (mínimo 3), para que el texto no cierre el bloque.
fence() {
  local text="$1" longest=0 run
  while IFS= read -r run; do
    [[ "${#run}" -gt "$longest" ]] && longest="${#run}"
  done < <(grep -o '`\+' <<<"$text" || true)
  local n=$((longest + 1))
  [[ "$n" -lt 3 ]] && n=3
  printf '%*s' "$n" '' | tr ' ' '`'
}

plan="$(cat "$plan_file")"
guard="$(cat "$guard_file")"

plan_notice=""
if [[ "${#plan}" -gt "$MAX_PLAN_CHARS" ]]; then
  total_chars="${#plan}"
  plan="${plan:0:MAX_PLAN_CHARS}"
  plan_notice="> **Aviso:** plan truncado a ${MAX_PLAN_CHARS} de ${total_chars} caracteres. Revisa el log del job para verlo completo."
fi

guard_notice=""
if [[ "${#guard}" -gt "$MAX_GUARD_CHARS" ]]; then
  total_chars="${#guard}"
  verdict="${guard##*$'\n'}"
  verdict="${verdict:0:200}"
  # Conserva el inicio de la lista y el veredicto final.
  guard="${guard:0:MAX_GUARD_CHARS-${#verdict}-5}"$'\n...\n'"${verdict}"
  guard_notice="> **Aviso:** guardia truncada a ${MAX_GUARD_CHARS} de ${total_chars} caracteres; se conserva el veredicto final. Revisa el log del job para la lista completa."
fi

guard_fence="$(fence "$guard")"
plan_fence="$(fence "$plan")"

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

{
  printf '%s\n' "$marker"
  printf '### Plan de OpenTofu: `%s`\n\n' "$stack"
  printf '**Guardia contra destrucciones**\n\n%stext\n%s\n%s\n\n' "$guard_fence" "$guard" "$guard_fence"
  if [[ -n "$guard_notice" ]]; then printf '%s\n\n' "$guard_notice"; fi
  if [[ -n "$plan_notice" ]]; then printf '%s\n\n' "$plan_notice"; fi
  printf '<details><summary>Plan completo</summary>\n\n%stext\n%s\n%s\n\n</details>\n' \
    "$plan_fence" "$plan" "$plan_fence"
} >"$body_file"

comments_path="repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments"

# Ids de los comentarios del autor que empiezan con el marcador del stack.
# Se leen completos y luego se toma el primero (sin head: evita SIGPIPE).
ids="$(gh api --paginate "$comments_path" \
  --jq ".[] | select(.user.login == \"${author}\" and (.body | startswith(\"${marker}\"))) | .id")" \
  || { echo "pr-comment: no se pudieron listar los comentarios del PR" >&2; exit 1; }
existing_id="${ids%%$'\n'*}"

payload() { jq -n --rawfile body "$body_file" '{body: $body}'; }

if [[ -n "$existing_id" ]]; then
  payload | gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${existing_id}" \
    --input - >/dev/null \
    || { echo "pr-comment: no se pudo reemplazar el comentario $existing_id" >&2; exit 1; }
  echo "pr-comment: comentario $existing_id reemplazado ($stack)"
else
  payload | gh api -X POST "$comments_path" --input - >/dev/null \
    || { echo "pr-comment: no se pudo crear el comentario" >&2; exit 1; }
  echo "pr-comment: comentario creado ($stack)"
fi
