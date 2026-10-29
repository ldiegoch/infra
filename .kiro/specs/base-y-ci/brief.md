# Brief: base-y-ci

## Problem
Solo GitHub Actions puede aplicar cambios (constitución, principio 2), pero
todavía no existe ni el CI ni la estructura donde vivirá la infraestructura.
Sin esta base, ninguna spec posterior puede llegar a la nube de forma segura.

## Current State
El repositorio tiene documentación, steering, ADR, la configuración de agentes
y `catalog/_template/app.yaml`. No hay stacks, `scripts/check.sh`, esquema,
`.sops.yaml`, hooks de pre-commit ni workflows (solo
`.github/pull_request_template.md`).

## Desired Outcome
- `platform/` y `apps/` existen sin recursos, con backend `s3` en R2
  (`use_lockfile = true`, una `key` por stack) y cifrado `pbkdf2` +
  `aes_gcm` con `enforced = true` para estado y plan, según
  `docs/plan.md` § "Estado remoto en R2".
- `.sops.yaml` con dos destinatarios age (las llaves públicas las da el
  humano; hasta entonces, marcadores claramente señalados).
- `schema/app.schema.json` valida el formato de `app.yaml` del plan.
- Hooks de pre-commit: fmt, gitleaks, verificación de cifrado SOPS y
  validación del esquema.
- `scripts/check.sh` corre todas las verificaciones con salida concisa.
- `pr.yml`: checks y `tofu plan` de ambos stacks comentado en el PR.
- `apply.yml`: en `main`, Environment `production`, Tailscale efímero con
  `tag:ci`, grupo de concurrencia `tofu-production`, `apply` de `platform/`
  y luego de `apps/`.
- La guardia analiza `tofu show -json` y falla si se destruye o reemplaza
  algo distinto de un contenedor sin la etiqueta `allow-destroy`.

## Approach
La de `docs/plan.md` § "Estado y secretos" y § "CI/CD". Acciones fijadas por
SHA, `permissions: contents: read` por defecto y permisos ampliados solo
donde se necesitan (comentar el PR). La lógica de la guardia se escribe de
forma que se pueda probar con planes JSON de ejemplo sin credenciales.

## Scope
- **In**: estructura de directorios, backends y cifrado, `.sops.yaml`,
  `.pre-commit-config.yaml`, `scripts/check.sh`, `schema/app.schema.json`,
  configuración de tflint y trivy, `pr.yml`, `apply.yml`, la guardia y sus
  pruebas con fixtures.
- **Out**: recursos reales en cualquiera de los stacks; crear el bucket, los
  tokens o el Environment (humano); `drift.yml`, `backup.yml`,
  `remove-app.yml`, `destroy.yml` (spec `backups-y-drift`); Renovate (spec
  `apps`).

## Boundary Candidates
- Backends y cifrado del estado.
- Verificación local (pre-commit + `check.sh` + esquema).
- Workflows de CI (`pr.yml`, `apply.yml`).
- Guardia contra destrucciones.

## Out of Boundary
- Lo que crean `platform/` y `apps/`.
- Protección de rama y configuración del repositorio en GitHub (humano).

## Upstream / Downstream
- **Upstream**: ADR 0001, 0006, 0007, 0009, 0010; cuentas y tokens del Paso 1.
- **Downstream**: todas las demás specs usan `check.sh`, el esquema y los
  workflows; `backups-y-drift` reutiliza el patrón de jobs del CI.

## Existing Spec Touchpoints
- **Extends**: ninguna.
- **Adjacent**: `apps` (consume y puede ampliar el esquema), `backups-y-drift`
  (más workflows).

## Constraints
- Sin credenciales: `tofu init -backend=false`; la variable
  `state_passphrase` existe pero solo el CI le da valor.
- Pendiente de verificar: si R2 acepta las escrituras condicionales de
  `use_lockfile`. El grupo de concurrencia es el respaldo.
- Puerta en la nube (humano): un PR de prueba muestra el `plan` vacío y un
  `secrets.enc.yaml` sin cifrar es rechazado.
