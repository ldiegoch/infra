# Roadmap

## Overview
Construir, como código, el host de apps Docker descrito en `docs/plan.md`:
un Droplet sin panel ni puertos de entrada, tráfico público por Cloudflare
Tunnel, administración por Tailscale, bases en Neon, secretos con SOPS + age,
estado cifrado en R2, observabilidad en Grafana Cloud y despliegue solo desde
GitHub Actions. Todo respeta `.kiro/steering/constitucion.md`.

El agente no tiene credenciales. Cada spec se da por implementada cuando
`scripts/check.sh` pasa (fmt, `tofu validate` con `init -backend=false`,
`tofu test` con `mock_provider`, tflint, trivy config, gitleaks) y
`/kiro-validate-impl` da `GO`. La "puerta" de cada fase en la nube (plan en
el PR, apply en CI, verificación real) la ejecuta el humano.

## Approach Decision
- **Chosen**: la arquitectura de `docs/plan.md` y los ADR 0001–0010, sin
  cambios: dos stacks (`platform/`, `apps/`) con estados separados,
  `modules/app` instanciado con `for_each` desde `catalog/*/app.yaml`, y el
  CI construido antes que el servidor.
- **Why**: está decidida y documentada en los ADR; el CI va primero porque
  solo GitHub Actions aplica cambios (constitución, principio 2).
- **Decisiones de esta sesión (2026-10-23)**:
  - Las reglas y paneles de Grafana como código viven en `platform/`. Son
    reglas genéricas agrupadas por la etiqueta `app` de los logs, así que
    cubren todas las apps sin recursos por app. Se mantienen los dos stacks.
  - Alloy se agrega a `cloud-init.yaml` en la spec `observabilidad`. Como el
    Droplet tiene `ignore_changes = [user_data]`, el cambio se aplica
    recreando el Droplet, con la etiqueta `allow-destroy` en ese PR y la
    explicación correspondiente.
- **Rejected alternatives**:
  - Un tercer stack `observability/`: cambia la arquitectura de dos stacks,
    requiere ADR y más jobs de CI sin un beneficio claro.
  - Alertas de Grafana en `modules/app`: más recursos y acoplan Grafana al
    ciclo de vida de cada app.
  - Preparar Alloy en `plataforma` para no recrear: mezcla responsabilidades
    entre specs, y el Droplet ya es desechable.

## Scope
- **In**: los stacks `platform/` y `apps/`, `modules/app`, el catálogo con la
  app de prueba `hola`, `schema/app.schema.json`, `scripts/check.sh`, los
  hooks de pre-commit, `.sops.yaml`, Renovate, los workflows `pr.yml`,
  `apply.yml`, `drift.yml`, `backup.yml`, `remove-app.yml` y `destroy.yml`,
  Alloy, las alertas (DigitalOcean, Grafana, Cloudflare) y los runbooks.
- **Out**: crear cuentas, tokens, el bucket `tofu-state` y el Environment
  `production` (lo hace el humano, Paso 1 de la guía); ejecutar `apply`; las
  apps reales distintas de `hola`; cualquier herramienta, provider o servicio
  que no esté en el plan sin un ADR.

## Constraints
- La constitución prevalece sobre cualquier spec.
- Sin credenciales: no se ejecuta `tofu plan` real, no hay `init` con backend
  y las pruebas usan solo providers simulados.
- Providers y versiones fijados (`required_providers` y
  `.terraform.lock.hcl`); acciones de GitHub fijadas por SHA; imágenes por
  digest.
- Documentación y specs en español; código y recursos en inglés o kebab-case.
- Credenciales que el plan no lista (por ejemplo los tokens de Grafana Cloud)
  se agregan a la tabla de credenciales del plan y las crea el humano.

## Boundary Strategy
- **Why this split**: sigue el radio de impacto (CI → servidor → apps →
  observabilidad → operación). Cada spec deja algo que se puede verificar en
  la nube por separado y se apoya solo en las salidas de las anteriores.
- **Shared seams to watch**:
  - `schema/app.schema.json`: lo crea `base-y-ci` (lo necesitan el hook y el
    CI) con el formato de `app.yaml` del plan; `apps` lo consume y lo amplía
    si hace falta.
  - Las salidas de `platform/` (nombre en Tailscale, ID del túnel, ID del
    Droplet) que lee `apps/`: es el contrato entre stacks.
  - `platform/cloud-init.yaml`: lo crea `plataforma` y lo amplía
    `observabilidad`.
  - La guardia contra destrucciones (`base-y-ci`) debe permitir el reemplazo
    de contenedores y bloquear el del Droplet sin `allow-destroy`.
  - `pr.yml` y `apply.yml` (`base-y-ci`) deben incorporar nuevos providers y
    variables de las specs posteriores sin rediseñarse.
  - Las etiquetas `app`/`service` de los contenedores (`apps`) son la base de
    las reglas de Grafana (`observabilidad`).

## Specs (dependency order)
- [ ] base-y-ci -- Estructura del repo, backends cifrados en R2, SOPS, pre-commit, check.sh, esquema de app.yaml, pr.yml, apply.yml y guardia contra destrucciones. Dependencies: none
- [ ] plataforma -- Stack platform/: Droplet con cloud-init endurecido, firewall sin entrada, Tailscale (llave y ACL), túnel de Cloudflare, alertas del host y salidas para apps/. Dependencies: base-y-ci
- [ ] apps -- Stack apps/ y modules/app: catálogo, cloudflared, redes edge y por app, contenedores, Neon con prevent_destroy, rutas del túnel, DNS, uptime checks, app hola y Renovate. Dependencies: base-y-ci, plataforma
- [ ] observabilidad -- Alloy por cloud-init y reglas, paneles y contactos de Grafana como código en platform/, más avisos de salud del túnel. Dependencies: plataforma, apps
- [ ] backups-y-drift -- backup.yml, copia diaria del estado, drift.yml, remove-app.yml, destroy.yml y runbooks. Dependencies: base-y-ci, plataforma, apps
