#!/usr/bin/env bash
# Pruebas de scripts/ci/pr-comment.sh (requisitos 6.2 y 6.3).
# Usa un `gh` simulado al inicio del PATH que guarda los comentarios en un
# archivo JSON local: sin red ni credenciales.
# Uso: bash scripts/tests/test_pr_comment.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../ci/pr-comment.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"

# gh simulado: solo entiende `gh api` sobre comentarios de issues.
# Estado en $FAKE_GH_STATE (arreglo JSON); cada llamada se anota en $FAKE_GH_LOG.
cat >"$FAKE_BIN/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
[[ "${1:-}" == "api" ]] || { echo "gh simulado: comando no soportado: $*" >&2; exit 90; }
shift
method="GET" path="" jq_expr="" input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X|--method) method="$2"; shift 2 ;;
    --jq|-q) jq_expr="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --paginate) shift ;;
    -H|--header) shift 2 ;;
    -*) echo "gh simulado: opción no soportada: $1" >&2; exit 91 ;;
    *) path="$1"; shift ;;
  esac
done
state="$FAKE_GH_STATE"
read_body() {
  if [[ "$input" == "-" ]]; then jq -r '.body'; else jq -r '.body' "$input"; fi
}
if [[ "$path" =~ ^repos/[^/]+/[^/]+/issues/[0-9]+/comments$ && "$method" == "GET" ]]; then
  if [[ -n "$jq_expr" ]]; then jq -r "$jq_expr" "$state"; else cat "$state"; fi
elif [[ "$path" =~ ^repos/[^/]+/[^/]+/issues/[0-9]+/comments$ && "$method" == "POST" ]]; then
  body="$(read_body)"
  next="$(jq '([.[].id] | max // 1000) + 1' "$state")"
  jq --argjson id "$next" --arg body "$body" --arg login "${FAKE_GH_LOGIN:-github-actions[bot]}" \
    '. + [{id: $id, body: $body, user: {login: $login}}]' \
    "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  jq -n --argjson id "$next" '{id: $id}'
elif [[ "$path" =~ ^repos/[^/]+/[^/]+/issues/comments/([0-9]+)$ && "$method" == "PATCH" ]]; then
  id="${BASH_REMATCH[1]}"
  jq -e --argjson id "$id" 'any(.[]; .id == $id)' "$state" >/dev/null \
    || { echo "gh simulado: comentario $id no existe" >&2; exit 92; }
  body="$(read_body)"
  jq --argjson id "$id" --arg body "$body" \
    'map(if .id == $id then .body = $body else . end)' \
    "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  jq -n --argjson id "$id" '{id: $id}'
else
  echo "gh simulado: ruta no soportada: $method $path" >&2
  exit 93
fi
FAKE
chmod +x "$FAKE_BIN/gh"

export FAKE_GH_STATE="$WORK/comments.json"
export FAKE_GH_LOG="$WORK/gh.log"
FAKE_TOKEN="fake-gh-token-not-real-0000"

# Comentario ajeno que nunca debe tocarse.
cat >"$FAKE_GH_STATE" <<'JSON'
[{"id": 1000, "body": "Comentario de una persona, sin marcador.", "user": {"login": "fake-owner"}}]
JSON
: >"$FAKE_GH_LOG"

PLAN1="$WORK/plan1.txt"
PLAN2="$WORK/plan2.txt"
PLAN_LONG="$WORK/plan-long.txt"
GUARD_OK="$WORK/guard-ok.txt"
GUARD_NO="$WORK/guard-no.txt"
printf 'No changes. Your infrastructure matches the configuration.\nfake-plan-v1\n' >"$PLAN1"
printf 'Plan: 1 to add, 0 to change, 0 to destroy.\nfake-plan-v2\n' >"$PLAN2"
printf 'APROBADO\n' >"$GUARD_OK"
printf 'delete digitalocean_droplet.fake (digitalocean_droplet)\nRECHAZADO: destrucción sin allow-destroy\n' >"$GUARD_NO"
{
  for i in $(seq 1 1500); do
    printf '  # fake_resource.r%04d will be created, filler line for truncation\n' "$i"
  done
  printf 'fake-plan-tail-marker\n'
} >"$PLAN_LONG"

passed=0
failed=0
out=""
code=0

# run_comment <stack> <plan> <guardia> [VAR=valor ...] (-VAR quita la variable)
run_comment() {
  local stack="$1" plan="$2" guard="$3"
  shift 3
  # env exige las opciones -u antes de las asignaciones.
  local -a unsets=() sets=("PATH=$FAKE_BIN:$PATH" "GH_TOKEN=$FAKE_TOKEN" "PR_NUMBER=42"
    "GITHUB_REPOSITORY=fake-owner/fake-repo")
  local kv
  for kv in "$@"; do
    if [[ "$kv" == -* ]]; then
      unsets+=(-u "${kv#-}")
      local keep=() s
      for s in "${sets[@]}"; do [[ "$s" == "${kv#-}="* ]] || keep+=("$s"); done
      sets=("${keep[@]}")
    else sets+=("$kv"); fi
  done
  out="$(env "${unsets[@]}" "${sets[@]}" bash "$SCRIPT" "$stack" "$plan" "$guard" 2>&1)"
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

calls() { wc -l <"$FAKE_GH_LOG" | tr -d ' '; }
count_marker() {
  jq --arg m "<!-- tofu-plan:$1 -->" '[.[] | select(.body | startswith($m))] | length' "$FAKE_GH_STATE"
}
body_of() {
  jq -r --arg m "<!-- tofu-plan:$1 -->" '.[] | select(.body | startswith($m)) | .body' "$FAKE_GH_STATE"
}
id_of() {
  jq -r --arg m "<!-- tofu-plan:$1 -->" '.[] | select(.body | startswith($m)) | .id' "$FAKE_GH_STATE"
}
total() { jq 'length' "$FAKE_GH_STATE"; }

# Variables de entorno obligatorias: falla sin llamar a gh y nombra la variable.
for var in GH_TOKEN PR_NUMBER GITHUB_REPOSITORY; do
  name="falta $var: falla sin llamar a gh"
  : >"$FAKE_GH_LOG"
  run_comment platform "$PLAN1" "$GUARD_OK" "-$var"
  if [[ "$code" -ne 0 ]] && grep -qF -- "$var" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
    ok "$name"
  else fail "$name"; fi
done

name="variable vacía cuenta como ausente"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN1" "$GUARD_OK" "PR_NUMBER="
if [[ "$code" -ne 0 ]] && grep -qF "PR_NUMBER" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

name="PR_NUMBER no numérico se rechaza"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN1" "$GUARD_OK" "PR_NUMBER=42/../x"
if [[ "$code" -ne 0 ]] && grep -qF "PR_NUMBER" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

name="stack desconocido se rechaza"
: >"$FAKE_GH_LOG"
run_comment staging "$PLAN1" "$GUARD_OK"
if [[ "$code" -ne 0 ]] && grep -qF "staging" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

name="plan inexistente se rechaza con la ruta"
: >"$FAKE_GH_LOG"
run_comment platform "$WORK/no-existe.txt" "$GUARD_OK"
if [[ "$code" -ne 0 ]] && grep -qF "no-existe.txt" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

name="faltan argumentos: muestra el uso"
: >"$FAKE_GH_LOG"
out="$(env "PATH=$FAKE_BIN:$PATH" GH_TOKEN="$FAKE_TOKEN" PR_NUMBER=42 \
  GITHUB_REPOSITORY=fake-owner/fake-repo bash "$SCRIPT" platform 2>&1)"
code=$?
if [[ "$code" -ne 0 ]] && grep -qi "uso" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

# 6.2: primera llamada crea el comentario con el plan y la guardia.
name="6.2 primera llamada crea el comentario de platform"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN1" "$GUARD_OK"
body="$(body_of platform)"
if [[ "$code" -eq 0 ]] && [[ "$(count_marker platform)" -eq 1 ]] && [[ "$(total)" -eq 2 ]] \
  && grep -qF "fake-plan-v1" <<<"$body" && grep -qF "APROBADO" <<<"$body" \
  && grep -q "POST" "$FAKE_GH_LOG" && ! grep -q "PATCH" "$FAKE_GH_LOG"; then
  ok "$name"
else fail "$name"; fi
first_id="$(id_of platform)"

# 6.3: segunda llamada reemplaza el mismo comentario.
name="6.3 segunda llamada reemplaza el comentario sin crear otro"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN2" "$GUARD_NO"
body="$(body_of platform)"
if [[ "$code" -eq 0 ]] && [[ "$(count_marker platform)" -eq 1 ]] && [[ "$(total)" -eq 2 ]] \
  && [[ "$(id_of platform)" == "$first_id" ]] \
  && grep -qF "fake-plan-v2" <<<"$body" && ! grep -qF "fake-plan-v1" <<<"$body" \
  && grep -qF "RECHAZADO: destrucción sin allow-destroy" <<<"$body" \
  && grep -q "PATCH" "$FAKE_GH_LOG" && ! grep -q "POST" "$FAKE_GH_LOG"; then
  ok "$name"
else fail "$name"; fi

name="el comentario ajeno queda intacto"
if [[ "$(jq -r '.[] | select(.id == 1000) | .body' "$FAKE_GH_STATE")" \
  == "Comentario de una persona, sin marcador." ]]; then
  ok "$name"
else fail "$name"; fi

# Un comentario por stack: apps no reemplaza al de platform.
name="6.2 apps crea su propio comentario"
: >"$FAKE_GH_LOG"
run_comment apps "$PLAN1" "$GUARD_OK"
if [[ "$code" -eq 0 ]] && [[ "$(count_marker apps)" -eq 1 ]] \
  && [[ "$(count_marker platform)" -eq 1 ]] && [[ "$(total)" -eq 3 ]] \
  && grep -qF "fake-plan-v2" <<<"$(body_of platform)"; then
  ok "$name"
else fail "$name"; fi

# Plan muy largo: se trunca con aviso y cabe en un comentario de GitHub.
name="plan largo se trunca con aviso"
: >"$FAKE_GH_LOG"
run_comment apps "$PLAN_LONG" "$GUARD_OK"
body="$(body_of apps)"
if [[ "$code" -eq 0 ]] && [[ "$(count_marker apps)" -eq 1 ]] \
  && [[ "${#body}" -lt 65536 ]] && grep -qi "truncado" <<<"$body" \
  && ! grep -qF "fake-plan-tail-marker" <<<"$body" \
  && grep -qF "fake_resource.r0001" <<<"$body" && grep -qF "APROBADO" <<<"$body"; then
  ok "$name"
else fail "$name"; fi

name="plan corto no lleva aviso de truncado"
if ! grep -qi "truncado" <<<"$(body_of platform)"; then
  ok "$name"
else fail "$name"; fi

name="el token nunca aparece en comentarios, salida ni argumentos de gh"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN1" "$GUARD_OK"
if [[ "$code" -eq 0 ]] && ! grep -qF "$FAKE_TOKEN" "$FAKE_GH_STATE" \
  && ! grep -qF "$FAKE_TOKEN" <<<"$out" && ! grep -qF "$FAKE_TOKEN" "$FAKE_GH_LOG"; then
  ok "$name"
else fail "$name"; fi

name="error de gh se propaga"
: >"$FAKE_GH_LOG"
cp "$FAKE_GH_STATE" "$WORK/state.bak"
echo 'no es json' >"$FAKE_GH_STATE"
run_comment platform "$PLAN1" "$GUARD_OK"
cp "$WORK/state.bak" "$FAKE_GH_STATE"
if [[ "$code" -ne 0 ]]; then
  ok "$name"
else fail "$name"; fi

# Filtro por autor: un comentario humano que empieza con el marcador no se toca.
cat >"$FAKE_GH_STATE" <<'JSON'
[{"id": 2000, "body": "<!-- tofu-plan:platform -->\nComentario humano con el marcador.", "user": {"login": "fake-owner"}}]
JSON
human_body="$(jq -r '.[0].body' "$FAKE_GH_STATE")"

name="comentario humano con marcador queda intacto y se crea el del bot"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN1" "$GUARD_OK"
bot_ids="$(jq -r '.[] | select(.user.login == "github-actions[bot]") | .id' "$FAKE_GH_STATE")"
if [[ "$code" -eq 0 ]] && [[ "$(total)" -eq 2 ]] \
  && [[ "$(jq -r '.[] | select(.id == 2000) | .body' "$FAKE_GH_STATE")" == "$human_body" ]] \
  && [[ -n "$bot_ids" ]] && grep -q "POST" "$FAKE_GH_LOG" && ! grep -q "PATCH" "$FAKE_GH_LOG"; then
  ok "$name"
else fail "$name"; fi

name="segunda llamada reemplaza el del bot, no el humano"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN2" "$GUARD_OK"
if [[ "$code" -eq 0 ]] && [[ "$(total)" -eq 2 ]] \
  && [[ "$(jq -r '.[] | select(.id == 2000) | .body' "$FAKE_GH_STATE")" == "$human_body" ]] \
  && grep -qF "issues/comments/$bot_ids" "$FAKE_GH_LOG" \
  && grep -qF "fake-plan-v2" <<<"$(jq -r --argjson id "$bot_ids" '.[] | select(.id == $id) | .body' "$FAKE_GH_STATE")"; then
  ok "$name"
else fail "$name"; fi

name="PR_COMMENT_AUTHOR cambia el autor buscado"
cat >"$FAKE_GH_STATE" <<'JSON'
[{"id": 3000, "body": "<!-- tofu-plan:apps -->\nviejo", "user": {"login": "fake-app[bot]"}},
 {"id": 3001, "body": "<!-- tofu-plan:apps -->\notro", "user": {"login": "github-actions[bot]"}}]
JSON
: >"$FAKE_GH_LOG"
run_comment apps "$PLAN1" "$GUARD_OK" "PR_COMMENT_AUTHOR=fake-app[bot]"
if [[ "$code" -eq 0 ]] && [[ "$(total)" -eq 2 ]] \
  && grep -qF "issues/comments/3000" "$FAKE_GH_LOG" \
  && [[ "$(jq -r '.[] | select(.id == 3001) | .body' "$FAKE_GH_STATE")" == $'<!-- tofu-plan:apps -->\notro' ]]; then
  ok "$name"
else fail "$name"; fi

name="PR_COMMENT_AUTHOR inválido se rechaza"
: >"$FAKE_GH_LOG"
run_comment apps "$PLAN1" "$GUARD_OK" 'PR_COMMENT_AUTHOR=x" or true'
if [[ "$code" -ne 0 ]] && grep -qF "PR_COMMENT_AUTHOR" <<<"$out" && [[ "$(calls)" -eq 0 ]]; then
  ok "$name"
else fail "$name"; fi

# Bloques de código: un plan o una guardia con ``` no cierran el bloque antes de tiempo.
echo '[]' >"$FAKE_GH_STATE"
PLAN_FENCE="$WORK/plan-fence.txt"
GUARD_FENCE="$WORK/guard-fence.txt"
printf 'fake-plan-first\n```\n</details>\n~~~ ```` x\nfake-plan-last\n' >"$PLAN_FENCE"
printf 'guard-first\n```\nguard-last\n' >"$GUARD_FENCE"

# fence_ok <cuerpo> <primera línea> <última línea>: la línea anterior a la
# primera abre un bloque y su cierre aparece una sola vez, justo tras la última.
fence_ok() {
  local b="$1" first="$2" last="$3" open fence
  open="$(grep -B1 -xF -- "$first" <<<"$b" | head -n 1)"
  fence="${open%text}"
  [[ "$fence" =~ ^(\`{3,}|~{3,})$ ]] || return 1
  [[ "$(grep -cxF -- "$fence" <<<"$b")" -eq 1 ]] || return 1
  [[ "$(grep -A1 -xF -- "$last" <<<"$b" | tail -n 1)" == "$fence" ]] || return 1
}

name="plan y guardia con \`\`\` quedan dentro de un solo bloque"
: >"$FAKE_GH_LOG"
run_comment platform "$PLAN_FENCE" "$GUARD_FENCE"
body="$(body_of platform)"
if [[ "$code" -eq 0 ]] && fence_ok "$body" "fake-plan-first" "fake-plan-last" \
  && fence_ok "$body" "guard-first" "guard-last" \
  && [[ "$(grep -cxF '</details>' <<<"$body")" -eq 2 ]]; then
  ok "$name"
else fail "$name"; fi

# Tamaño total: guardia enorme más plan largo caben en un comentario.
GUARD_BIG="$WORK/guard-big.txt"
{
  for i in $(seq 1 800); do
    printf 'delete digitalocean_droplet.fake%04d (digitalocean_droplet)\n' "$i"
  done
  printf 'RECHAZADO: destrucción sin allow-destroy\n'
} >"$GUARD_BIG"

name="guardia enorme más plan largo: cuerpo bajo 65 536 caracteres"
: >"$FAKE_GH_LOG"
run_comment apps "$PLAN_LONG" "$GUARD_BIG"
body="$(body_of apps)"
if [[ "$code" -eq 0 ]] && [[ "${#body}" -lt 65536 ]] \
  && grep -qi "guardia truncada" <<<"$body" && grep -qi "plan truncado" <<<"$body" \
  && grep -qxF "RECHAZADO: destrucción sin allow-destroy" <<<"$body" \
  && ! grep -qF "digitalocean_droplet.fake0800" <<<"$body" \
  && grep -qF "fake_resource.r0001" <<<"$body"; then
  ok "$name"
else fail "$name"; fi

echo "resultado: $passed pasaron, $failed fallaron"
[[ "$failed" -eq 0 ]]
