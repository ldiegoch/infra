---
paths: [".github/workflows/**"]
---
# workflows.md
- Fija cada acción por SHA de commit (los esqueletos del plan usan tags
  solo por legibilidad).
- permissions mínimos: contents: read por defecto.
- Credenciales solo desde los Environments production (apply) y plan
  (plan de PR del mismo repositorio, ADR 0011); nunca imprimirlas.
- Todo workflow que aplica o destruye usa concurrency: tofu-production,
  a nivel de workflow o de job, sin repetirla en ambos.
