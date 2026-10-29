# Brief: backups-y-drift

## Problem
Sin respaldo independiente, detección de cambios manuales ni procedimientos
controlados de retiro y destrucción, un error o un incidente puede perder
datos o dejar configuración fuera de Git.

## Current State
Existen los stacks, `pr.yml`/`apply.yml` y la guardia. No hay `pg_dump`,
copia del estado, detección de drift ni workflows de retiro o destrucción, y
`docs/runbooks/` solo tiene la plantilla.

## Desired Outcome
Según `docs/plan.md` § "Backups y recuperación", § "Remover una app" y el
Paso 6 de la guía:
- `backup.yml` diario: `pg_dump` de cada base Neon, cifrado con age y subido
  a R2 con retención de 30 días; si falla, el humano recibe el correo de
  GitHub Actions.
- Copia diaria con fecha del estado de ambos stacks, con 30 días de
  retención.
- `drift.yml` diario: `tofu plan -detailed-exitcode` de ambos stacks; si hay
  diferencias, abre un issue.
- `remove-app.yml`: quita la base de una app del estado con confirmación
  escrita, después de que la app salió del catálogo.
- `destroy.yml`: destrucción controlada según el Paso 6 de la guía.
- Runbooks: restauración de `pg_dump` en una rama de Neon, recreación del
  Droplet, rotación de un secreto filtrado y respuesta a drift.

## Approach
Workflows con el mismo patrón de seguridad que `base-y-ci` (acciones por
SHA, permisos mínimos, Environment `production`, grupo de concurrencia
compartido con `apply.yml` cuando tocan el estado). `remove-app.yml` y
`destroy.yml` solo con `workflow_dispatch` y confirmación escrita.

## Scope
- **In**: los cuatro workflows, la copia del estado, la retención en R2, los
  runbooks y las actualizaciones de documentación.
- **Out**: restaurar de verdad (simulacro humano); backups de disco del
  Droplet (ya activados en `plataforma`).

## Boundary Candidates
- Respaldo de datos (`backup.yml`).
- Respaldo del estado.
- Detección de drift.
- Operaciones destructivas controladas (`remove-app.yml`, `destroy.yml`).
- Runbooks.

## Out of Boundary
- Cambios a la lógica de los stacks o del módulo, salvo las salidas que
  necesite el backup.

## Upstream / Downstream
- **Upstream**: `base-y-ci` (patrón de CI y guardia), `plataforma`, `apps`
  (bases Neon y procedimiento de retiro); ADR 0005, 0007, 0009.
- **Downstream**: operación diaria y simulacro trimestral.

## Existing Spec Touchpoints
- **Extends**: `apps` (salidas para enumerar las bases, si hacen falta).
- **Adjacent**: `base-y-ci` (workflows existentes).

## Constraints
- Decisiones abiertas para el diseño: en qué bucket viven los `pg_dump` y las
  copias del estado (la llave de R2 actual solo alcanza `tofu-state`), cómo
  se aplica la regla de ciclo de vida de 30 días y cómo obtiene `backup.yml`
  las credenciales de Neon sin exponerlas. Si alguna exige un recurso o
  servicio nuevo, va con ADR.
- `remove-app.yml` usa `tofu state rm`: solo lo ejecuta el CI, lo lanza el
  humano y el agente nunca lo corre.
- Puerta en la nube (humano): simulacro de restauración de un `pg_dump` en
  una rama de Neon.
