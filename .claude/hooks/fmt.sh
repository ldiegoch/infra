#!/usr/bin/env bash
# Hook PostToolUse(Edit|Write|MultiEdit): formatea solo el archivo editado,
# y solo si es OpenTofu. Nunca bloquea ni imprime nada.
f=$(jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
case "$f" in
  *.tf|*.tfvars|*.tftest.hcl) command -v tofu >/dev/null && tofu fmt "$f" >/dev/null 2>&1 ;;
esac
exit 0
