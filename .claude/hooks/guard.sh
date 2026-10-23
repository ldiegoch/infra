#!/usr/bin/env bash
# Hook PreToolUse(Bash). Recibe la llamada en JSON por stdin.
# Salir con 2 bloquea el comando y muestra el motivo al agente.
# Falla cerrado: si no puede leer la llamada, bloquea.
set -uo pipefail

block() {
  echo "Bloqueado: $1" >&2
  echo "Si es texto (p. ej. un mensaje de commit), reescríbelo sin esa palabra o comando." >&2
  exit 2
}

input=$(cat) || block "no se pudo leer la llamada."
command -v jq >/dev/null 2>&1 || block "falta jq; el hook no puede revisar el comando."
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) \
  || block "JSON de la llamada inválido."

# 1. Solo el CI aplica cambios o modifica el estado.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_-])(tofu|terraform)([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+(apply|destroy|import|state|force-unlock|taint|untaint)([[:space:]"'\'')]|$)'; then
  block "solo el CI aplica cambios o modifica el estado."
fi

# 2. El agente no maneja secretos ni llaves.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]/"'\''(`])(sops|age|age-keygen)([[:space:]"'\'')]|$)|\.dec\.|keys\.txt|\.agekey|SOPS_AGE_KEY|sops/age'; then
  block "el agente no maneja secretos."
fi

# 3. Acciones de GitHub que equivalen a desplegar o a cambiar credenciales.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+(pr[[:space:]]+merge|workflow[[:space:]]+(run|enable)|run[[:space:]]+rerun|secret|variable|api|ruleset|repo[[:space:]]+(edit|delete))([[:space:]]|$)'; then
  block "fusionar, lanzar workflows o tocar secretos de GitHub lo hace el humano."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]].*allow-destroy'; then
  block "la etiqueta allow-destroy la pone el humano."
fi

# 4. Git: sin saltarse hooks, sin force-push y sin push directo a main.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]].*--no-verify'; then
  block "no se omiten los hooks de pre-commit."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]].*)?[[:space:]](-f|--force|--force-with-lease[^[:space:]]*|--mirror|--delete)([[:space:]]|$)'; then
  block "sin force-push ni borrado de ramas remotas."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]].*)?[[:space:]:+](main|HEAD:main)([[:space:]]|$)'; then
  block "main solo cambia por PR."
fi

# 5. El agente no modifica su propio contrato de seguridad.
if printf '%s' "$cmd" | grep -Eq '\.claude/(settings[^[:space:]]*\.json|hooks/)'; then
  if ! printf '%s' "$cmd" | grep -Eq '^[[:space:]]*(cat|head|tail|grep|jq|ls|bash[[:space:]]+\.claude/hooks/guard\.test\.sh)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '>|[;&|]|\btee\b'; then
    block ".claude/settings.json y .claude/hooks/ solo los edita el humano."
  fi
fi

exit 0
