---
paths: [".github/workflows/**"]
---
# workflows.md
- Fija cada acción por SHA de commit (los esqueletos del plan usan tags
  solo por legibilidad).
- permissions mínimos: contents: read por defecto.
- Credenciales solo desde el Environment production; nunca imprimirlas.
- Todo job que aplica o destruye usa concurrency: tofu-production.
