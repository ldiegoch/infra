---
paths: ["**/*.tf", "**/*.tftest.hcl"]
---
# opentofu.md
- Fija la versión de cada provider en required_providers y conserva
  .terraform.lock.hcl.
- Variables con type y description; las sensibles con sensitive = true.
- Usa for_each con claves estables del catálogo, no count, para apps.
- Cada módulo tiene pruebas en tests/*.tftest.hcl con mock_provider.
- Un cambio de apps/ nunca toca platform/, y viceversa.
