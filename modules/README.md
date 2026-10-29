# Módulos de OpenTofu

Módulos reutilizables que consumen los stacks `platform/` y `apps/`.

- `modules/app` llega con la spec `apps`.
- Cada módulo incluye pruebas en `tests/*.tftest.hcl` con `mock_provider`,
  sin tocar recursos reales (ver `.claude/rules/opentofu.md`).
