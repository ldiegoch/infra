# Research & Design Decisions: base-y-ci

## Summary
- **Feature**: `base-y-ci`
- **Discovery Scope**: New Feature (greenfield; descubrimiento completo)
- **Key Findings**:
  - R2 acepta las escrituras condicionales que usa `use_lockfile`, así que
    no hace falta DynamoDB. R2 no tiene versioning: la copia del estado es
    responsabilidad de `backups-y-drift`.
  - En un repo privado con GitHub Pro existen Environments con reglas de
    rama, pero no revisores obligatorios. Para `pull_request`, la regla se
    evalúa contra `refs/pull/N/merge` (cambio de dic. 2025).
  - `tofu init -backend=false`, `validate`, `fmt` y `tflint` funcionan sin
    la frase de cifrado. Las verificaciones locales no necesitan
    credenciales.

## Research Log

### Bloqueo del estado en R2
- **Context**: requisito 2.4 y la duda pendiente de `tech.md`.
- **Sources Consulted**: https://developers.cloudflare.com/r2/api/s3/api/ ·
  https://github.com/opentofu/opentofu/issues/2605
- **Findings**: PutObject con `If-None-Match: *` es atómico en el endpoint
  S3 de R2 (gana uno, los demás reciben 412). El bug de `skip_s3_checksum`
  con lock-file se corrigió antes de la 1.10. R2 no soporta versioning,
  tagging ni SSE-KMS.
- **Implications**: `use_lockfile = true` con la configuración de R2 del
  plan y sin `lock_tags`. El humano hace una única prueba con credenciales
  reales. El grupo de concurrencia queda como segunda barrera (req. 2.5).

### Cifrado del estado con variable
- **Context**: requisitos 2.2, 2.3 y 5.2.
- **Sources Consulted**: https://opentofu.org/docs/language/state/encryption/;
  prueba local con OpenTofu 1.12.6.
- **Findings**: `passphrase = var.state_passphrase` funciona desde la 1.8.
  Sin valor, `init -backend=false`, `validate`, `fmt` y `tflint` pasan.
  `init` con backend y `plan` fallan. `pbkdf2` exige al menos 16
  caracteres.
- **Implications**: la variable es `sensitive`, con `validation` de longitud
  mínima 16. El CI la pasa como `TF_VAR_state_passphrase`.

### Configuración parcial del backend
- **Context**: el endpoint de R2 contiene el account ID.
- **Sources Consulted**: https://opentofu.org/docs/language/settings/backends/s3/
- **Findings**: el endpoint se puede pasar con `AWS_ENDPOINT_URL_S3` y las
  credenciales con `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY`. Lo que se
  pasa por `-backend-config` queda guardado en `.terraform/`.
- **Implications**: `backend.tf` lleva solo `bucket`, `key`, `region` y los
  `skip_*`. El endpoint y las claves llegan como variables de entorno desde
  el Environment.

### Acciones del plan JSON
- **Context**: requisito 8.
- **Sources Consulted**: https://opentofu.org/docs/internals/json-format/
- **Findings**: las acciones posibles son `no-op`, `create`, `read`,
  `update`, `delete`, `["delete","create"]`, `["create","delete"]` y
  `forget`. Cualquier destrucción contiene `"delete"`.
- **Implications**: la guardia marca un recurso si `"delete"` o `"forget"`
  aparece en `actions` y su tipo no es `docker_container`. `forget` saca un
  recurso del control de OpenTofu, así que se trata con el mismo cuidado.

### Tailscale en GitHub Actions
- **Context**: requisito 7.3.
- **Sources Consulted**: https://github.com/tailscale/github-action
- **Findings**: la versión actual es `v4`. Recibe `oauth-client-id`,
  `oauth-secret` y `tags`. Los nodos son efímeros y un paso post hace logout
  aunque el job falle. El cliente OAuth necesita el scope `auth_keys`.
- **Implications**: la acción va fijada por SHA y con `tags: tag:ci`. Usa el
  cliente OAuth del plan. OIDC queda como mejora futura, con ADR.

### PR asociado a un commit de main
- **Context**: requisito 8.4.
- **Sources Consulted**: https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit
- **Findings**: `GET /repos/{o}/{r}/commits/{sha}/pulls` devuelve el PR
  fusionado con sus `labels` y requiere `pull-requests: read`. Puede llegar
  vacío justo después de la fusión.
- **Implications**: hasta 3 reintentos y, si no hay PR, resultado
  `unknown`. Con `unknown`, la guardia rechaza cualquier destrucción que no
  sea de un contenedor.

### Environments en un repo privado con Pro
- **Context**: requisitos 6.5 y 7.2; ADR 0009.
- **Sources Consulted**: https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/ ·
  https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- **Findings**: Pro permite Environments y reglas de rama en repos privados,
  pero no revisores obligatorios. En `pull_request` la regla se compara con
  `refs/pull/N/merge`; el patrón `refs/pull/*/merge` funciona.
- **Implications**: `production` queda restringido a `main` y `plan` a
  `refs/pull/*/merge`. La aprobación humana de los PR es la fusión misma.
  La aprobación con "Required reviewers" que da por hecha la guía no está
  disponible: lo registra el ADR 0011 y `backups-y-drift` lo resuelve con
  confirmación escrita.

### Concurrencia de GitHub Actions
- **Context**: requisito 7.4.
- **Findings**: un grupo de concurrencia admite una ejecución en curso y una
  pendiente. Una nueva ejecución reemplaza a la pendiente.
- **Implications**: con `cancel-in-progress: false`, la ejecución en curso
  nunca se cancela. La pendiente que sobrevive es la más reciente de `main`
  e incluye los cambios anteriores. El requisito 7.4 se precisó con este
  comportamiento.

### Stacks sin providers
- **Findings**: `tofu init` sin providers no crea `.terraform.lock.hcl` y
  `plan` informa "no changes".
- **Implications**: `check.sh` exige el lock file solo en los stacks que
  declaran `required_providers`.

### Herramientas del dev container
- **Findings**: el Dockerfile fija tofu 1.12.6, sops 3.13.3, age 1.3.2,
  trivy 0.76.1, gitleaks 8.30.1 y tflint 0.64.0. `pre-commit`, `python3`,
  `python3-yaml` y `jq` vienen de apt. `python3-jsonschema` no está
  instalado (Ubuntu 24.04 ofrece la 4.10.3).
- **Implications**: hace falta un validador de JSON Schema; queda en el
  ADR 0012.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Checks dentro de la imagen del dev container | El CI construye `.devcontainer/Dockerfile` y corre `check.sh` dentro | Una sola fuente de versiones, sin acciones extra | Unos minutos de build por PR | Elegida |
| Acciones `setup-*` por herramienta | Una acción por herramienta | Más rápido | Versiones duplicadas y más acciones de terceros | Descartada para checks; `setup-opentofu` se usa solo en plan/apply |
| Workflow reutilizable por stack | `_tofu-stack.yml` (`workflow_call`) para plan y apply | Una sola lógica de init/plan/guardia | Un archivo más | Elegida |
| Lógica duplicada en `pr.yml` y `apply.yml` | Pasos copiados | Archivos autocontenidos | Divergencias entre plan y apply | Descartada |

## Design Decisions

### Decision: Environment `plan` para los PR (ADR 0011)
- **Context**: el plan en cada PR necesita credenciales, pero `production`
  solo está disponible para `main`.
- **Alternatives Considered**:
  1. Abrir `production` a los PR: un PR alcanzaría credenciales de escritura.
  2. Plan solo en `main`: no se revisa el plan antes de fusionar.
- **Selected Approach**: un Environment `plan` restringido a
  `refs/pull/*/merge`, con credenciales de solo lectura donde el proveedor
  lo permita. Nunca ejecuta apply. No corre en PR de forks.
- **Rationale**: es el menor privilegio compatible con revisar el plan.
- **Trade-offs**: `plan` necesita la frase del estado (y con ella acceso de
  lectura a los secretos del estado). Desde la spec `apps`, también la llave
  SSH de `deploy`, que tiene control de Docker. Sin revisores obligatorios
  (plan Pro), la protección es que solo el dueño abre PR en el repo privado.
- **Follow-up**: cada spec que agregue un provider documenta qué credencial
  de solo lectura va en `plan`.

### Decision: validador de `app.yaml` (ADR 0012)
- **Context**: requisito 4. El dev container no tiene validador de JSON
  Schema.
- **Alternatives Considered**:
  1. `check-jsonschema` desde PyPI o pre-commit: otra descarga y otra versión
     que fijar.
  2. `ajv` con Node: un paquete npm y un `package.json` en el repo.
  3. Validar con `check`/`validation` de OpenTofu en `apps/`: no corre en
     pre-commit y duplica el esquema.
- **Selected Approach**: el paquete `python3-jsonschema` de apt (Ubuntu
  24.04) más `scripts/check_catalog.py`, que valida contra
  `schema/app.schema.json` y además revisa las reglas que JSON Schema no
  expresa (nombre igual a la carpeta).
- **Rationale**: Python y PyYAML ya están en la imagen. Un paquete de la
  distribución queda fijado por la imagen base y no agrega gestores nuevos.
- **Trade-offs**: la versión depende de Ubuntu 24.04 (4.10.3, que soporta
  Draft 2020-12).

### Decision: generalización de la verificación
- Las mismas verificaciones corren en tres lugares (pre-commit, `check.sh` y
  CI). Hay un único script por verificación; pre-commit y `check.sh` lo
  invocan, y el CI corre `check.sh`.
- La guardia es un solo script, usado por el plan del PR y por el apply.

### Decision: simplificación
- No se crean plugins de tflint, configuración de gitleaks ni acciones de
  comentario de terceros. El comentario del PR se publica con `gh api`
  (preinstalado en los runners).

## Risks & Mitigations
- Build de la imagen en cada PR (lento): se acepta. Optimizar con caché solo
  si molesta.
- tflint podría marcar `state_passphrase` como no usada (no entiende el
  bloque `encryption`): se usa un comentario `tflint-ignore` con
  justificación.
- Trivy descarga su base de checks: sin red falla y `check.sh` lo dice
  explícitamente (req. 5.5).
- Un PR con `allow-destroy` reemplazado en la cola de concurrencia: la
  guardia del siguiente apply rechaza la destrucción (falla cerrada) y el
  humano decide.
- El plan JSON contiene valores sensibles en claro: nunca se sube como
  artefacto ni se publica, y se borra al terminar el job.

## References
- ADR 0006, 0007, 0009, 0010 · `docs/plan.md` § Estado y secretos, § CI/CD
- https://opentofu.org/docs/language/state/encryption/
- https://opentofu.org/docs/internals/json-format/
- https://github.com/tailscale/github-action

---

# Gap Analysis (2026-10-27)

> Hecho después del diseño y las tareas, a pedido. Confirma el enfoque y
> agrega restricciones del código existente; no reabre decisiones.

## Estado actual
- Proyecto greenfield en IaC: no hay `.tf`, scripts, esquema ni workflows.
- Activos que la spec debe respetar o reutilizar:
  - `.devcontainer/Dockerfile`: herramientas fijadas con checksum y líneas
    `renovate:`. Es la base del job `checks`.
  - `.devcontainer/devcontainer.json:17`: `pre-commit install` solo corre si
    existe la configuración, al iniciar el contenedor.
  - `.gitignore`: ya ignora estado, planes `*.tfplan`/`*.tfplan.json`,
    `.terraform/`, archivos descifrados y llaves age.
  - `.github/pull_request_template.md`: su checklist ya exige `check.sh`,
    revisión del plan y `allow-destroy`; encaja con la guardia.
  - `CLAUDE.md`, `.claude/agents/catalog-editor.md:8,18` y
    `.claude/rules/catalog.md:5` ya nombran `scripts/check.sh` y
    `schema/app.schema.json`; las rutas del diseño coinciden.
  - `.claude/rules/opentofu.md` y `.claude/rules/workflows.md`: reglas que el
    diseño cumple (lock file, variables tipadas, SHA, `tofu-production`).
  - `.claude/hooks/fmt.sh`: formatea al editar; complementa `fmt -check`.
  - `catalog/_template/app.yaml`: usa marcadores (`CAMBIAR`, `DIGEST`) que
    fallarían el esquema; queda ignorada por empezar con `_`.

## Mapa requisito → activo

| Req | Activo existente | Brecha |
|-----|------------------|--------|
| 1 | `.gitignore`, `.gitattributes` | Missing: stacks, `modules/` |
| 2 | — | Missing: backend y cifrado. Constraint: R2 sin versioning |
| 3 | `.gitignore` (llaves, descifrados) | Missing: `.sops.yaml`, verificación |
| 4 | `_template/app.yaml` (formato de facto) | Missing: esquema y validador (ADR 0012) |
| 5 | Dockerfile, `fmt.sh`, `postStartCommand` | Missing: `check.sh`, `.pre-commit-config.yaml` |
| 6–8 | Plantilla de PR | Missing: workflows y guardia |
| 9 | `.claude/rules/workflows.md` | Missing: pruebas estáticas |
| 10 | ADR 0000–0010, plan § Credenciales | Missing: ADR 0011. Constraint: Pro sin revisores obligatorios |

## Opciones
- **A. Extender lo existente** (validaciones en el Dockerfile o en hooks de
  Claude): ✅ menos archivos. ❌ los hooks de `.claude/` solo los edita el
  humano y no corren en el CI; mezcla responsabilidades.
- **B. Todo nuevo, sin tocar nada existente**: ❌ no es viable; el validador
  exige cambiar el Dockerfile y la documentación de credenciales debe
  actualizarse.
- **C. Híbrido (el del diseño)**: componentes nuevos más cambios acotados al
  Dockerfile, `.gitignore` y la documentación. ✅ respeta los activos y sus
  dueños.

## Esfuerzo y riesgo
- **Esfuerzo: M (3–7 días)**: muchas piezas pequeñas con patrones conocidos;
  los workflows no se pueden probar de punta a punta sin credenciales.
- **Riesgo: Medio**: la integración real (Environments, R2, Tailscale) solo
  se verifica en la puerta humana; la lógica crítica (guardia y validadores)
  sí se prueba localmente.

## Research Needed / restricciones nuevas
- **Hook de seguridad (Constraint)**: el agente no puede leerlo y ya bloqueó
  comandos de esta sesión: `gh api` sobre Environments, lecturas de
  `.claude/hooks/` y un heredoc con palabras vigiladas. Durante `/kiro-impl`
  algún comando de las tareas podría quedar bloqueado (por ejemplo, escribir
  scripts o fixtures por shell). Mitigación: crear archivos con las
  herramientas de edición; si un comando necesario queda bloqueado, el
  agente se detiene y lo explica, sin rodearlo.
- **Docker local (Constraint)**: el dev container no tiene Docker, así que el
  job `checks` (build de la imagen) solo se prueba en el CI; localmente se
  corre `check.sh` directamente.
- **`tofu test` sin módulos**: el paso imprime "omitido" hasta la spec
  `apps`; no es una brecha.
