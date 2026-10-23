#!/usr/bin/env bash
# Pruebas del hook guard.sh: bash .claude/hooks/guard.test.sh
# shellcheck disable=SC2016  # los $ literales son intencionales
# Imprime solo los fallos y un resumen.
cd "$(dirname "$0")" || exit 1
fail=0; total=0
check() { # check <esperado: block|allow> <comando>
  total=$((total+1))
  jq -n --arg c "$2" '{tool_input:{command:$c}}' | bash guard.sh >/dev/null 2>&1
  rc=$?; got=allow; [ "$rc" -eq 2 ] && got=block
  [ "$got" = "$1" ] || { echo "FALLO: esperaba $1, obtuve $got: $2"; fail=$((fail+1)); }
}
# Debe bloquear
check block 'tofu apply'
check block 'tofu -chdir=apps apply -auto-approve'
check block 'tofu -chdir=platform -var x=1 destroy'
check block 'terraform import foo bar'
check block 'tofu state rm module.app'
check block 'tofu force-unlock 123'
check block 'bash -c "tofu apply"'
check block 'cd apps && tofu apply'
check block "sh -c 'tofu destroy'"
check block 'bash -c "sops -d x.enc.yaml"'
check block 'x=$(sops -d f)'
check block 'sops -d catalog/hola/secrets.enc.yaml'
check block 'sops catalog/hola/secrets.enc.yaml'
check block '/usr/local/bin/sops -d x'
check block 'age -d -i key.txt backup.age'
check block 'age-keygen -o k'
check block 'cat ~/.config/sops/age/keys.txt'
check block 'cat secrets.dec.yaml'
check block 'echo $SOPS_AGE_KEY'
check block 'gh pr merge 12 --squash'
check block 'gh workflow run destroy.yml -f stack=apps'
check block 'gh run rerun 999'
check block 'gh secret list'
check block 'gh api repos/x/y/environments'
check block 'gh pr edit 12 --add-label allow-destroy'
check block 'git commit --no-verify -m x'
check block 'git push --force origin feat/x'
check block 'git push -f'
check block 'git push origin main'
check block 'git push origin HEAD:main'
check block 'sed -i s/deny/allow/ .claude/settings.json'
check block 'echo {} > .claude/settings.json'
check block 'rm .claude/hooks/guard.sh'
check block 'cat .claude/settings.json > /tmp/x'
# Debe permitir
check allow 'tofu fmt -recursive'
check allow 'tofu -chdir=apps init -backend=false'
check allow 'tofu -chdir=apps validate'
check allow 'tofu -chdir=modules/app test'
check allow 'tofu plan -destroy -out=x'
check allow './scripts/check.sh'
check allow 'tflint --recursive'
check allow 'trivy config .'
check allow 'gitleaks detect --no-banner'
check allow 'cat .sops.yaml'
check allow 'grep -rn sops_file apps/'
check allow 'git status'
check allow 'git push -u origin feat/base-y-ci'
check allow 'git switch -c feat/maintenance'
check allow 'gh pr view 12 --comments'
check allow 'gh pr create --draft --fill'
check allow 'cat .claude/settings.json'
check allow 'bash .claude/hooks/guard.test.sh'
check allow 'grep -n deny .claude/settings.json'
echo "guard.sh: $((total-fail))/$total pruebas OK"
[ "$fail" -eq 0 ]
