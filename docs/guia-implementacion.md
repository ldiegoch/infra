# Guía de implementación

## Resumen y requisitos

Esta guía lleva el plan de cero a producción en seis pasos, con Claude Code escribiendo el código mediante cc-sdd y tú aprobando cada fase. En tu computadora solo instalas Docker, VS Code y Git; todo lo demás vive en un dev container que puedes borrar y reconstruir en minutos.

Tres reglas de seguridad guían todo el proceso:

- **El dev container no tiene credenciales de producción.** Claude puede escribir y validar código, pero no puede crear, cambiar ni destruir infraestructura aunque lo intente.
- **Solo GitHub Actions aplica cambios**, y solo después de que fusionas un PR con el `plan` revisado.
- **Claude nunca ve secretos.** Los archivos de SOPS los editas tú; el agente solo conoce los nombres de las variables.

| Necesitas en tu equipo | Para qué |
| --- | --- |
| Docker Desktop (o Docker Engine en Linux) | Ejecutar el dev container |
| VS Code con la extensión Dev Containers | Abrir el proyecto dentro del contenedor |
| Git | Clonar el repositorio |
| Un gestor de contraseñas | Guardar llaves age, la frase del estado y los tokens |
| Una suscripción de Claude (Pro o Max) o una clave de API | Usar Claude Code |

Orden de los pasos: cuentas y tokens → dev container → proyecto con cc-sdd → especificaciones e implementación por fase → operación diaria → destrucción controlada cuando la necesites.

## Paso 1: cuentas y tokens

Crea las cuentas en este orden, activa 2FA en cada una antes de generar cualquier token y guarda cada valor directo en tu gestor de contraseñas. Ningún token va a tu computadora ni al dev container: al final de este paso los cargas en GitHub.

1. **GitHub**
   - Crea el repositorio privado `infra` y dos GitHub Environments (Settings → Environments; ADR 0011):
     - `production`: en "Deployment branches and tags" elige "Selected branches and tags" y agrega solo la rama `main`. Lo usa `apply.yml`.
     - `plan`: misma opción, con la regla `refs/pull/*/merge` y nada más. Lo usa `pr.yml` para el plan de los PR; nunca corre para forks.
   - GitHub Pro no ofrece revisores obligatorios (required reviewers) en Environments de repos privados: no los busques. La protección real es la de `main`.
   - Protege `main`: PR obligatorio, checks en verde (`checks` y el plan de ambos stacks), sin force-push y sin push directo. Así, un PR no puede cambiar `apply.yml` ni usar `production` sin pasar por la fusión.
   - Crea un ruleset de ramas (Settings → Rules → Rulesets) que prohíba crear ramas que coincidan con `refs/**`. La regla del Environment `plan` se compara con nombres de rama, y una rama llamada literalmente `refs/pull/1/merge` podría usar `plan` desde un push. Compruébalo en la prueba única: intentar `git push origin HEAD:refs/heads/refs/pull/1/merge` debe ser rechazado.
   - Crea un token de solo lectura de paquetes (`read:packages`) para descargar imágenes de GHCR.
2. **DigitalOcean**
   - Regístrate, activa 2FA y agrega un método de pago y una alerta de facturación (por ejemplo, $40).
   - Crea un proyecto llamado `apps`.
   - Sube tu llave SSH pública de administrador (Settings → Security) y anota su ID.
   - Genera un token de API con scopes personalizados (Droplets, firewalls, monitoreo, uptime, proyectos, llaves SSH) y expiración de 90 días.
3. **Cloudflare** (ya tienes la cuenta)
   - Anota el Account ID y el Zone ID de tu dominio.
   - Activa Zero Trust en el plan gratuito (lo requiere Cloudflare Tunnel).
   - Crea un token de API con: DNS de tu zona (editar), Cloudflare Tunnel (editar) y R2 (editar).
   - Crea el bucket R2 `tofu-state` y, aparte, el bucket `backups`. Genera dos tokens de API de R2 con permiso "Object Read & Write" limitados a `tofu-state`: uno para `production` y otro para `plan` (el plan también toma el bloqueo del estado). Anota de cada uno el Access Key ID y el Secret Access Key, y el endpoint S3 `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.
4. **Neon**
   - Crea la organización, anota el `org_id` y genera una llave de API.
5. **Tailscale**
   - Crea la red, activa MagicDNS y define en la política los tags `tag:server` y `tag:ci`.
   - Crea un cliente OAuth para `production` con permiso para crear llaves de autenticación con esos tags y para editar la política (ACL).
   - Crea otro cliente OAuth para `plan` que solo cree llaves con `tag:ci` y solo lea la política.
   - Instala Tailscale en tu computadora (es lo único extra) para entrar al servidor en emergencias.
6. **Grafana Cloud**
   - Crea un stack en la región de EE. UU.
   - Genera un token de política de acceso con escritura de logs y métricas (para Alloy) y un token de service account (para el provider de Terraform).
7. **Llaves locales de cifrado** (se generan dentro del dev container en el paso 2)
   - Dos llaves age: la tuya y la del CI.
   - La frase de cifrado del estado: 32 caracteres aleatorios o más.

Al terminar, carga los secretos en GitHub (Settings → Environments → cada Environment → Environment secrets), nunca como secretos del repositorio. Hoy `.github/workflows/_tofu-stack.yml` usa estos nombres, que deben existir en **ambos** Environments con exactamente este nombre:

| Secreto | Valor en `production` | Valor en `plan` |
| --- | --- | --- |
| `R2_ACCESS_KEY_ID` | Access Key ID del token R2 de `production` | Access Key ID del token R2 de `plan` |
| `R2_SECRET_ACCESS_KEY` | Secret Access Key del token R2 de `production` | Secret Access Key del token R2 de `plan` |
| `R2_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` | El mismo |
| `TF_STATE_PASSPHRASE` | La frase de cifrado del estado | La misma (riesgo aceptado en el ADR 0011) |
| `TS_OAUTH_CLIENT_ID` | ID del cliente OAuth de Tailscale de `production` | ID del cliente OAuth de `plan` |
| `TS_OAUTH_SECRET` | Secreto del cliente OAuth de `production` | Secreto del cliente OAuth de `plan` |

Si falta alguno, el job falla y muestra solo el nombre que falta. El resto (token de DigitalOcean, token de Cloudflare, llave de Neon, tokens de Grafana, token de GHCR, llave age del CI y llave SSH del usuario `deploy`) se carga cuando la spec que lo usa fija su nombre; el alcance de cada uno en `production` y en `plan` está en docs/plan.md, "Credenciales de la plataforma".

**Prueba única del bloqueo en R2.** La documentación indica que R2 acepta las escrituras condicionales que usa `use_lockfile`, pero se comprueba una vez, cuando ya existan los workflows de la spec `base-y-ci`:

1. Abre dos PR de prueba (por ejemplo, un cambio de comentario en cada uno) y empújalos casi a la vez para que el plan de `platform` corra en paralelo.
2. Mientras corren, revisa en el panel de R2 que aparece `platform/terraform.tfstate.tflock` en `tofu-state` (dura pocos segundos) y que ya no está al terminar.
3. Ambos planes deben terminar bien: el segundo espera el bloqueo hasta 5 minutos. Confirma también en el log que el job usó el Environment `plan`: si la regla `refs/pull/*/merge` no admite la ejecución del PR, el job queda rechazado por la regla de rama del Environment y hay que corregirla. Si algún plan falla con un error al crear el bloqueo, R2 no lo soporta: avísale a Claude para proponer un ADR que desactive `use_lockfile`; mientras tanto, el grupo de concurrencia `tofu-production` sigue impidiendo dos `apply` a la vez.
4. Cierra los PR sin fusionar.

## Paso 2: dev container

Todas las herramientas (OpenTofu, SOPS, age, tflint, Trivy, gitleaks, pre-commit, Claude Code y Node para cc-sdd) viven en un contenedor definido en el propio repositorio. Si algo se rompe, "Rebuild Container" lo deja como nuevo, y borrar el contenedor y sus volúmenes no deja rastro en tu equipo.

1. Clona el repositorio vacío `infra` y crea la carpeta `.devcontainer/` con los dos archivos de abajo.
   > Versión vigente: `.devcontainer/` del repositorio (versiones fijadas y checksums verificados). Los bloques de abajo son la referencia original.
2. En VS Code: "Dev Containers: Reopen in Container". La primera construcción tarda unos minutos.
3. En la terminal del contenedor, ejecuta `claude` e inicia sesión; la sesión se guarda en un volumen y sobrevive a las reconstrucciones.
4. Genera las llaves age (`age-keygen`) **y guárdalas en tu gestor de contraseñas**; nunca las dejes en un archivo dentro del contenedor.

```json
// .devcontainer/devcontainer.json
{
  "name": "infra",
  "build": { "dockerfile": "Dockerfile" },
  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "lts" },
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  },
  "containerEnv": {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "mounts": [
    "source=infra-claude-config,target=/home/vscode/.claude,type=volume"
  ],
  "postCreateCommand": "pre-commit install",
  "remoteUser": "vscode"
}
```

```dockerfile
# .devcontainer/Dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
ARG TARGETARCH
# Fija cada versión en la última estable; Renovate las actualiza por PR.
ARG TOFU_VERSION=X.Y.Z
ARG SOPS_VERSION=X.Y.Z
ARG AGE_VERSION=X.Y.Z
ARG TRIVY_VERSION=X.Y.Z
ARG GITLEAKS_VERSION=X.Y.Z

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates jq unzip pre-commit && rm -rf /var/lib/apt/lists/*

# OpenTofu (instalador oficial)
RUN curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/tofu.sh \
 && sh /tmp/tofu.sh --install-method standalone --opentofu-version ${TOFU_VERSION} \
 && rm /tmp/tofu.sh

# SOPS y age
RUN curl -fsSLo /usr/local/bin/sops \
      https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH} \
 && chmod +x /usr/local/bin/sops \
 && curl -fsSL https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${TARGETARCH}.tar.gz \
    | tar -xz -C /tmp && mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/

# tflint, Trivy y gitleaks
RUN curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash \
 && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin v${TRIVY_VERSION} \
 && GL_ARCH=$([ "$TARGETARCH" = "amd64" ] && echo x64 || echo arm64) \
 && curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin gitleaks
```

Cómo editar secretos sin que el agente los vea:

- Abre una **terminal aparte** en VS Code (no la de Claude), pega tu llave age como variable de entorno (`export SOPS_AGE_KEY=...`), ejecuta `sops catalog/<app>/secrets.enc.yaml` y cierra esa terminal al terminar.
- La variable solo existe en esa terminal; la sesión de Claude Code nunca la recibe.

Para borrar todo el entorno local: "Dev Containers: Rebuild Container Without Cache" o, para eliminarlo por completo, borra el contenedor y el volumen `infra-claude-config` desde Docker.

## Paso 3: crear el proyecto con Claude Code y cc-sdd

cc-sdd (v3) instala en el repositorio un flujo de desarrollo guiado por especificaciones: descubrimiento → requisitos → diseño → tareas → implementación, con tu aprobación entre fases. Las especificaciones quedan en `.kiro/specs/` y la "memoria" del proyecto (steering) en `.kiro/steering/`.

1. **Lleva este plan al repositorio.** Exporta este documento a Markdown y guárdalo como `docs/plan.md`. Es la fuente que Claude leerá para todo lo demás.
2. **Instala cc-sdd** en la terminal del contenedor:

   ```bash
   npx cc-sdd@latest --claude-skills --lang es
   ```

   Instala las skills `/kiro-*` en `.claude/skills/` y las plantillas y reglas en `.kiro/settings/`.
3. **Crea la configuración de agentes** (pestaña "Configuración de agentes"). Abre `claude` y usa este prompt:

   ```text
   Lee docs/plan.md, en especial la pestaña "Configuración de agentes".
   Crea exactamente los archivos que ahí se definen: CLAUDE.md,
   .claude/settings.json, .claude/hooks/guard.sh, .claude/agents/*.md,
   .claude/rules/*.md, docs/adr/0000-plantilla.md, los ADR 0001 a 0010,
   catalog/_template/app.yaml, .github/pull_request_template.md y
   docs/runbooks/plantilla.md. No inventes contenido que no esté en el
   plan; si algo falta, déjalo marcado como TODO y dime qué falta.
   No ejecutes tofu ni sops.
   ```
4. **Reinicia Claude Code** (sal y vuelve a entrar) para que cargue los permisos y hooks nuevos. Comprueba que funcionan pidiendo `ejecuta tofu apply`: el hook debe bloquearlo.
5. **Genera la memoria del proyecto:**

   ```text
   /kiro-steering
   Usa docs/plan.md como fuente. El repositorio aún no tiene código:
   describe el producto, la tecnología y la estructura que el plan define.
   ```

   ```text
   /kiro-steering-custom
   Crea .kiro/steering/constitucion.md con los principios no negociables
   de la pestaña "Configuración de agentes" (sección Constitución), tal
   cual están escritos, y .kiro/steering/seguridad.md con el checklist de
   seguridad del plan.
   ```
6. **Revisa y confirma.** Lee los archivos de `.kiro/steering/`; edítalos si algo no refleja tus decisiones. Haz el primer commit en una rama y abre el PR. A partir de aquí, todo cambio pasa por PR.

## Paso 4: especificaciones e implementación por fase

El trabajo se divide en cinco specs, y el CI va primero: como solo GitHub Actions puede aplicar cambios, debe existir antes de crear el servidor. Cada spec sigue el mismo ciclo, con tu revisión en cada flecha:

```text
/kiro-spec-init → /kiro-spec-requirements → /kiro-spec-design → /kiro-spec-tasks
  → /kiro-impl → /kiro-validate-impl → PR → plan en CI → fusión → apply en CI
```

Qué revisar en cada puerta:

- **requirements.md:** que diga lo mismo que el plan; nada de herramientas o servicios que no estén ahí.
- **design.md:** que el plan de archivos respete la estructura del repositorio y que cualquier decisión nueva traiga su ADR.
- **tasks.md:** tareas pequeñas, cada una con su verificación (`scripts/check.sh` o `tofu test`).
- **Resultado de /kiro-validate-impl:** solo seguir con `GO`.

### Arranque

```text
/kiro-discovery
Construir la infraestructura de docs/plan.md respetando
.kiro/steering/constitucion.md. Divídela en estas specs, en este orden:
base-y-ci, plataforma, apps, observabilidad, backups-y-drift.
El agente no tiene credenciales: las pruebas son tofu validate, tofu test
con providers simulados, tflint, trivy config y gitleaks.
```

### Spec 1: `base-y-ci`

```text
/kiro-spec-init base-y-ci
Estructura del repositorio según docs/plan.md. Backend S3 en R2 con
use_lockfile y cifrado de estado obligatorio (pbkdf2 + aes_gcm), para los
stacks platform/ y apps/ (todavía sin recursos). .sops.yaml con dos
destinatarios age (los públicos te los doy yo). Hooks de pre-commit: fmt,
gitleaks, verificación de cifrado SOPS y esquema JSON de app.yaml.
scripts/check.sh que corre todas las verificaciones. Workflows pr.yml
(checks + plan comentado en el PR) y apply.yml (Tailscale tag:ci, grupo de
concurrencia, environment production) y la guardia contra destrucciones.
```

Puerta: un PR de prueba muestra el `plan` vacío y un archivo de secretos sin cifrar es rechazado.

### Spec 2: `plataforma`

```text
/kiro-spec-init plataforma
Stack platform/ según la sección "Stack de plataforma" de docs/plan.md:
llave de Tailscale de un solo uso, Droplet con cloud-init endurecido,
firewall sin reglas de entrada, ACL de Tailscale, túnel de Cloudflare y
alertas de CPU, memoria y disco. Salidas para el stack apps/.
```

Puerta: tras fusionar y aplicar, entras por SSH solo vía Tailscale, un escaneo de puertos desde Internet no encuentra nada y las alertas de prueba llegan a tu correo.

### Spec 3: `apps`

```text
/kiro-spec-init apps
Stack apps/ y modules/app según la sección "Stack de apps" de
docs/plan.md: catálogo YAML, cloudflared, red edge, red por app,
contenedores, proyecto Neon con prevent_destroy, rutas del túnel y DNS
por hostname, uptime checks. Incluye una app de prueba catalog/hola con
nginx y el campo enabled para desactivar apps.
```

Puerta: `hola.tudominio.com` responde, un hostname no declarado devuelve 404 y el chequeo de disponibilidad está en verde. Después agrega tu primera app real con el Paso 5.

### Spec 4: `observabilidad`

```text
/kiro-spec-init observabilidad
Grafana Alloy instalado por cloud-init (logs de contenedores y sistema,
métricas del host) y reglas de alerta y paneles de Grafana como código
con el provider de Grafana, según la tabla de "Logs, métricas y
alertas" de docs/plan.md.
```

Puerta: ves los logs de `hola` en Grafana y una alerta de prueba llega a tu correo.

### Spec 5: `backups-y-drift`

```text
/kiro-spec-init backups-y-drift
Workflows backup.yml (pg_dump diario de cada base Neon, cifrado con age,
subido a R2 con retención de 30 días), drift.yml (plan diario con aviso),
copia diaria del estado, remove-app.yml (quita la base del estado con
confirmación escrita) y destroy.yml según el Paso 6 de la guía.
```

Puerta: completas un simulacro de restauración de un `pg_dump` en una rama de Neon.

## Paso 5: operación diaria

Los cambios del día a día no necesitan una spec completa: los hace el subagente `catalog-editor`, y tú solo revisas el PR y su `plan`. Los valores de los secretos siempre los escribes tú, en una terminal aparte.

### Agregar una app

```text
Usa el subagente catalog-editor para agregar la app "facturacion":
- web: imagen ghcr.io/miusuario/facturacion-web@sha256:<digest>, puerto 3000,
  pública en facturacion.midominio.com, healthcheck /health, 256 MB.
- api: imagen ghcr.io/miusuario/facturacion-api@sha256:<digest>, puerto 8080,
  interna, 256 MB, usa base de datos Neon, secreto Stripe__ApiKey.
Crea la rama, el app.yaml y un secrets.enc.yaml con solo los nombres de las
variables. Corre scripts/check.sh y prepara el commit.
```

Después: llena el valor del secreto con `sops` en una terminal aparte, haz push, abre el PR y revisa que el `plan` solo cree recursos de `facturacion`.

### Cambiar configuración

```text
Usa el subagente catalog-editor: en la app "facturacion", sube la memoria de
la api a 384 MB y agrega la variable FEATURE_PAGOS=true. Corre
scripts/check.sh y prepara el commit.
```

Las versiones nuevas de imágenes no necesitan prompt: Renovate abre el PR con el digest nuevo.

### Entender un plan antes de fusionar

```text
Usa el subagente iac-reviewer para explicarme en lenguaje simple el plan
del PR #<número>: qué se crea, qué cambia, qué se reemplaza y qué se
destruye. Señala cualquier cosa fuera de la app que estoy cambiando.
```

### Remover una app

```text
Usa el subagente catalog-editor para preparar la eliminación de la app
"facturacion": verifica que backup.yml tenga un respaldo de las últimas
24 horas, crea la rama que borra catalog/facturacion y recuérdame los pasos
manuales del procedimiento de remoción de docs/plan.md.
```

Después: ejecutas `remove-app.yml` desde GitHub (quita la base del estado sin borrarla), abres el PR con la etiqueta `allow-destroy` y fusionas. Para solo pausar una app, pide poner `enabled: false`.

### Diagnosticar un fallo

```text
El apply del PR #<número> falló con este error: <pega el log>.
Explícame la causa en lenguaje simple y propón la corrección en una rama
nueva. Si la causa es el estado o un recurso en la nube, no intentes
arreglarlo: dime qué debo revisar yo.
```

## Paso 6: destruir todo de forma controlada

La destrucción también la ejecuta solo el CI, con un workflow manual que exige escribir una confirmación y tu aprobación en GitHub. Primero se destruyen las apps, luego la plataforma, y al final lo que no gestiona OpenTofu.

```yaml
# .github/workflows/destroy.yml (esqueleto)
name: destroy
on:
  workflow_dispatch:
    inputs:
      stack:
        type: choice
        options: [apps, platform]
      confirm:
        description: "Escribe destruir-<stack> para confirmar"
        required: true
jobs:
  destroy:
    if: inputs.confirm == format('destruir-{0}', inputs.stack)
    environment: production        # solo main; Pro no ofrece revisores obligatorios en repos privados (ADR 0011): protegen main y el workflow_dispatch manual
    concurrency: tofu-production
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: tailscale/github-action@v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - uses: opentofu/setup-opentofu@v1
      - run: tofu -chdir=${{ inputs.stack }} init
      - run: tofu -chdir=${{ inputs.stack }} destroy -auto-approve
        # + las variables de entorno con las credenciales del Environment
```

Orden para borrar todo:

- [ ] Ejecuta `backup.yml` y descarga una copia de los respaldos de R2 si quieres conservarlos.
- [ ] Ejecuta `remove-app.yml` para cada app con base de datos (las bases tienen `prevent_destroy` y quedan intactas en Neon).
- [ ] `destroy.yml` con `apps`: desaparecen contenedores, rutas del túnel, DNS y chequeos de disponibilidad.
- [ ] `destroy.yml` con `platform`: desaparecen el Droplet, el firewall, el túnel y las alertas.
- [ ] Borra a mano los proyectos de Neon cuando ya no necesites los datos.
- [ ] Revoca los tokens de DigitalOcean, Cloudflare, Neon, Grafana y GHCR, y el cliente OAuth de Tailscale; elimina el servidor de tu red de Tailscale.
- [ ] Borra los buckets de R2: primero `backups` y al final `tofu-state`.
- [ ] Borra el contenedor y el volumen `infra-claude-config` en tu equipo.

Para rehacer todo desde cero, el repositorio en GitHub tiene la configuración completa: crea el bucket del estado, vuelve a cargar los tokens y fusiona cualquier PR para que el CI recree la plataforma y las apps.
