# Plan: host de apps Docker con OpenTofu, Cloudflare y Neon

Oct 23, 2026 · @Diego

## Resumen y decisión de arquitectura

La recomendación es un Droplet de DigitalOcean **sin panel de administración**, con toda la infraestructura y todas las apps definidas en OpenTofu (compatible con Terraform) y desplegadas desde GitHub Actions. Cada app es una carpeta con un archivo YAML en Git: agregarla, cambiarla o quitarla es un pull request.

Por qué sin panel (en lugar de Dokploy):

- **Seguridad:** Dokploy y Coolify han tenido vulnerabilidades críticas en 2026. Sin panel, no existe una interfaz de administración que atacar.
- **Todo como código:** no hay un provider de Terraform para Dokploy; solo existe uno comunitario para Pulumi (v0.3.1). El provider de Docker para Terraform (`kreuzwerker/docker`) maneja los contenedores directamente.
- **Cero puertos abiertos:** el tráfico público entra por Cloudflare Tunnel y la administración por Tailscale.

Lo que se pierde es la interfaz gráfica de despliegue. Logs, métricas y alertas se ven en Grafana Cloud.

| Pieza | Elección | Motivo |
| --- | --- | --- |
| Infraestructura como código | OpenTofu 1.10 o superior | Mismos providers que Terraform, cifrado de estado nativo y bloqueo en S3 sin DynamoDB |
| Servidor | Droplet de 4 GB en `nyc3` | Cerca de Neon `aws-us-east-1`; se amplía a 8 GB cuando crezca |
| Runtime | Docker, gestionado con `kreuzwerker/docker` vía SSH sobre Tailscale | Sin agentes ni paneles extra |
| Entrada pública | Cloudflare Tunnel, un hostname explícito por app | Sin puertos abiertos ni DNS comodín |
| Base de datos | Neon, un proyecto por app (`kislerdm/neon`) | Aislamiento y credenciales por app |
| Secretos | SOPS + age, cifrados dentro del repositorio | Versionados junto a la configuración, nunca en texto plano |
| Estado | Cloudflare R2, cifrado por OpenTofu | Fuera de DigitalOcean: si se pierde el Droplet o la cuenta, se reconstruye |
| Observabilidad | Grafana Cloud (agente Alloy) + alertas de DigitalOcean | Logs fuera del servidor y alertas por correo |
| CI/CD | GitHub Actions + Renovate | Plan en cada PR, apply al fusionar, actualizaciones de imágenes por PR |

Paso a paso desde cero: [docs/guia-implementacion.md](guia-implementacion.md). Reglas y configuración de los agentes de IA: [docs/configuracion-agentes.md](configuracion-agentes.md).

## Componentes y flujo de tráfico

```text
Usuarios ──HTTPS──▶ Cloudflare (DNS, WAF) ──Tunnel──▶ cloudflared ─┐
                                                                    │ red "edge"
                         Droplet apps-1 (sin puertos de entrada)    ▼
                         ┌───────────────────────────────────────────────┐
                         │ <app>-web (public: true) ── red app-<app> ──▶ │
                         │ <app>-api (public: false, solo red de su app) │
                         │ Grafana Alloy (logs y métricas)               │
                         └───────────────────────────────────────────────┘
GitHub Actions ──Tailscale (tag:ci)──▶ SSH deploy@apps-1 (provider Docker)
<app>-api ──▶ Neon (un proyecto por app)      Alloy ──▶ Grafana Cloud
Estado de OpenTofu y pg_dump cifrados ──▶ Cloudflare R2
```

Los usuarios solo llegan a los servicios públicos a través de Cloudflare; las APIs quedan en la red interna de su app. Tú administras todo desde GitHub Actions por Tailscale, y el estado y los backups viven fuera de DigitalOcean.

## Estructura del repositorio y formato `app.yaml`

Un solo repositorio privado (`infra`) es la única fuente de verdad: nada se configura a mano en el servidor. Hay dos stacks con estados separados, para que un error en una app nunca toque la red o el servidor.

```text
infra/
  platform/            # Droplet, firewall, Tailscale, túnel, alertas del servidor
    main.tf  cloud-init.yaml  backend.tf
  apps/                # contenedores, rutas del túnel, Neon, uptime checks
    main.tf  tunnel.tf  backend.tf
  modules/
    app/               # un módulo reutilizable por app
  catalog/
    _template/
      app.yaml
    facturacion/
      app.yaml         # configuración (sin secretos)
      secrets.enc.yaml # secretos cifrados con SOPS
  .sops.yaml           # qué llaves age pueden descifrar
  renovate.json
  .github/workflows/  pr.yml  apply.yml  drift.yml  backup.yml
```

Cada app declara sus servicios (por ejemplo, frontend y API). Solo los servicios con `public: true` reciben un hostname; los demás quedan en la red interna de su app.

```yaml
# catalog/facturacion/app.yaml
name: facturacion
database:
  neon: true            # crea un proyecto Neon y entrega DATABASE_URL
services:
  web:
    image: ghcr.io/miusuario/facturacion-web@sha256:<digest>
    port: 3000
    public: true
    hostname: facturacion.midominio.com
    healthcheck: /health
    memory_mb: 256
    env:
      API_URL: http://facturacion-api:8080
  api:
    image: ghcr.io/miusuario/facturacion-api@sha256:<digest>
    port: 8080
    public: false
    memory_mb: 256
    uses_database: true
    env:
      ASPNETCORE_ENVIRONMENT: Production
      DOTNET_gcServer: "0"
    secrets:            # solo nombres; los valores están en secrets.enc.yaml
      - Stripe__ApiKey
```

Reglas del catálogo:

- Las imágenes se fijan por **digest** (`@sha256:`), nunca `:latest`, para que un redespliegue no traiga una imagen sin revisar.
- `app.yaml` nunca contiene valores secretos; el CI rechaza el PR si encuentra uno.
- Las carpetas que empiezan con `_` se ignoran (plantillas).

## Estado y secretos

Los secretos viven cifrados en Git con SOPS + age, y el estado de OpenTofu vive cifrado en Cloudflare R2. Nadie copia una contraseña a mano: lo que se puede generar (URL de Neon, token del túnel) lo genera OpenTofu y lo inyecta directo al contenedor.

### Estado remoto en R2

El bucket `tofu-state` se crea una sola vez a mano (es el huevo y la gallina). Cada stack usa su propia llave.

```hcl
terraform {
  backend "s3" {
    bucket    = "tofu-state"
    key       = "apps/terraform.tfstate"   # platform/terraform.tfstate en el otro stack
    region    = "auto"
    endpoints = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
    use_path_style              = true
    use_lockfile                = true      # bloqueo nativo, OpenTofu 1.10+
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase     # viene del CI, nunca del repo
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
```

- El estado contiene secretos (variables de entorno de los contenedores), por eso el cifrado es obligatorio (`enforced = true`).
- Además del bloqueo, el CI usa un grupo de concurrencia de GitHub Actions: nunca corren dos `apply` a la vez.
- R2 es compatible con las escrituras condicionales que usa `use_lockfile` según la documentación, pendiente de la prueba única del Paso 1 de la guía. Si falla, el grupo de concurrencia `tofu-production` basta para el `apply`, porque solo el CI aplica cambios.

### Secretos de las apps con SOPS + age

- Dos destinatarios en `.sops.yaml`: tu llave age personal (guardada en tu gestor de contraseñas) y la llave age del CI.
- Editar: `sops catalog/facturacion/secrets.enc.yaml` abre el archivo descifrado en tu editor y lo guarda cifrado. Los nombres de las variables quedan visibles, así que los PR muestran *qué* secreto cambió sin revelar su valor.
- OpenTofu los lee con el provider `carlpett/sops` (data source `sops_file`) y los pasa al contenedor que los declara en `secrets:`.
- Un hook de pre-commit y el CI rechazan cualquier `secrets.enc.yaml` sin metadatos de SOPS (o sea, en texto plano), y `gitleaks` revisa todo el repositorio.

### Credenciales de la plataforma

Viven en dos GitHub Environments, que crea el humano (Paso 1 de la guía) y que usan los mismos nombres de secretos; cada Environment tiene sus propios valores y, donde el proveedor lo permite, los de `plan` son de solo lectura (ADR 0011):

- `production`: solo la rama `main`. Lo usa `apply.yml`; tiene las credenciales con escritura.
- `plan`: solo la regla `refs/pull/*/merge`. Lo usa `pr.yml` para el plan de los PR del mismo repositorio, nunca de forks. Sus credenciales son de solo lectura donde el proveedor lo permite.

Secretos que usa hoy `.github/workflows/_tofu-stack.yml` (crea cada uno en ambos Environments):

| Secreto | Credencial | Alcance en `production` | Alcance en `plan` |
| --- | --- | --- | --- |
| `R2_ACCESS_KEY_ID` | Llave de acceso a R2 (ID) | Lectura y escritura de objetos, solo el bucket `tofu-state` | Igual que `production`, con una llave propia: el plan toma el bloqueo del estado |
| `R2_SECRET_ACCESS_KEY` | Llave de acceso a R2 (secreto) | Par de la anterior | Par de la anterior |
| `R2_ENDPOINT` | Endpoint S3 de R2 (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`) | No es una credencial; se guarda como secreto para no fijar el Account ID en el repo | Mismo valor |
| `TF_STATE_PASSPHRASE` | Frase de cifrado del estado (llega como `TF_VAR_state_passphrase`) | Cifrar y descifrar estado y plan | Mismo valor: no hay variante de solo lectura (riesgo aceptado en el ADR 0011) |
| `TS_OAUTH_CLIENT_ID` | Cliente OAuth de Tailscale (ID) | Crear llaves con `tag:server` y `tag:ci` y editar la política | Cliente propio: crear llaves solo con `tag:ci` y leer la política |
| `TS_OAUTH_SECRET` | Cliente OAuth de Tailscale (secreto) | Par del anterior | Par del anterior |

Credenciales que agregan las specs siguientes; cada spec fija el nombre del secreto, lo mapea en `_tofu-stack.yml` y lo crea en ambos Environments:

| Credencial | Alcance en `production` | Alcance en `plan` |
| --- | --- | --- |
| Token de DigitalOcean | Scopes personalizados: Droplets, firewalls, monitoreo, uptime | Los mismos scopes, solo lectura |
| Token de API de Cloudflare | DNS de tu zona, Cloudflare Tunnel y el bucket R2 del estado | Token propio con DNS y Cloudflare Tunnel en lectura |
| Llave de API de Neon | Tu organización de Neon | Solo lectura si Neon la ofrece; si no, una llave propia con el mismo alcance (pendiente de decisión, ADR 0011) |
| Llave age del CI | Descifrar el catálogo | Misma llave: el plan de `apps` lee el catálogo (pendiente de decisión, ADR 0011) |
| Llave SSH del usuario `deploy` | Solo ese usuario en el Droplet | Misma llave: el plan de `apps` consulta Docker por SSH (riesgo aceptado en el ADR 0011) |
| Token de lectura de GHCR | `read:packages`, para descargar imágenes privadas | El mismo alcance, que ya es de solo lectura |
| Tokens de Grafana Cloud | Escritura de logs y métricas (Alloy) y service account para el provider | Solo el service account, con rol de lectura si alcanza para el plan |

Sin la frase de cifrado y tu llave age personal no se puede leer el estado ni los secretos: guárdalas en tu gestor de contraseñas antes del primer `apply`.

## Stack de plataforma

El stack `platform/` crea el servidor y todo lo que no depende de las apps; cambia pocas veces. El Droplet se trata como desechable: si algo raro pasa, se recrea con `apply` en lugar de repararlo a mano.

Recursos que crea:

- Droplet Ubuntu 24.04 de 4 GB con backups semanales de DigitalOcean y agente de monitoreo.
- Cloud Firewall **sin ninguna regla de entrada**; solo salida.
- Llave de Tailscale de un solo uso con `tag:server`, y la ACL de Tailscale que permite a `tag:ci` y a tu usuario llegar al puerto 22 del servidor, y a nada más.
- El túnel de Cloudflare (sus rutas las define el stack de apps).
- Alertas de CPU, memoria y disco del Droplet por correo.

```hcl
# platform/main.tf (esqueleto)
resource "tailscale_tailnet_key" "server" {
  reusable      = false
  preauthorized = true
  expiry        = 3600
  tags          = ["tag:server"]
}

resource "digitalocean_droplet" "host" {
  name       = "apps-1"
  region     = "nyc3"
  size       = "s-2vcpu-4gb"
  image      = "ubuntu-24-04-x64"
  ssh_keys   = [var.admin_ssh_key_id]
  monitoring = true
  backups    = true
  user_data  = templatefile("${path.module}/cloud-init.yaml", {
    tailscale_auth_key = tailscale_tailnet_key.server.key
    deploy_ssh_pubkey  = var.deploy_ssh_pubkey
  })
  lifecycle { ignore_changes = [user_data] }   # cambiar cloud-init = recrear a propósito
}

resource "digitalocean_firewall" "host" {
  name        = "apps-sin-entrada"
  droplet_ids = [digitalocean_droplet.host.id]
  # Sin inbound_rule: nada entra desde Internet.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = "apps-1"
  config_src = "cloudflare"
}

resource "digitalocean_monitor_alert" "memory" {
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = 85
  window      = "10m"
  entities    = [digitalocean_droplet.host.id]
  description = "Memoria del host por encima de 85 %"
  enabled     = true
  alerts { email = [var.alert_email] }
}
# + alertas iguales para CPU y disco
```

Qué hace `cloud-init.yaml` en el primer arranque:

1. Crea el usuario `deploy` (grupo `docker`) con tu llave pública; SSH solo con llaves, sin `root` y sin contraseñas.
2. Activa `unattended-upgrades` con reinicio automático de madrugada.
3. Instala Docker Engine con `daemon.json` endurecido: `live-restore`, sin `userland-proxy` y rotación de logs (10 MB × 3).
4. Instala Tailscale y se une a tu red con la llave de un solo uso.
5. Instala fail2ban como defensa adicional.

Salidas del stack que usa `apps/`: el nombre del servidor en Tailscale (`apps-1`), el ID del túnel y el ID del Droplet.

Acceso de emergencia: si Tailscale falla, la Recovery Console de DigitalOcean entra sin abrir ningún puerto.

## Stack de apps

El stack `apps/` lee todas las carpetas de `catalog/` y crea, por cada app, sus contenedores, su red, su base Neon, sus rutas en el túnel y sus chequeos de disponibilidad. Una app nueva en el catálogo aparece en el `plan`; una carpeta borrada aparece como destrucción.

### Raíz del stack

```hcl
# apps/main.tf (esqueleto)
provider "docker" {
  host     = "ssh://deploy@apps-1:22"          # nombre del servidor en Tailscale
  ssh_opts = ["-o", "StrictHostKeyChecking=yes"]
  registry_auth {
    address  = "ghcr.io"
    username = var.ghcr_user
    password = var.ghcr_token
  }
}

locals {
  catalog = "${path.module}/../catalog"
  apps = {
    for f in fileset(local.catalog, "*/app.yaml") :
    dirname(f) => yamldecode(file("${local.catalog}/${f}"))
    if !startswith(dirname(f), "_")
  }
  public_services = merge([
    for app, spec in local.apps : {
      for svc, s in spec.services : "${app}-${svc}" => s if try(s.public, false)
    }
  ]...)
}

data "sops_file" "secrets" {
  for_each    = { for app, spec in local.apps : app => spec
                  if fileexists("${local.catalog}/${app}/secrets.enc.yaml") }
  source_file = "${local.catalog}/${each.key}/secrets.enc.yaml"
}

resource "docker_network" "edge" { name = "edge" }   # solo cloudflared + servicios públicos

resource "docker_container" "cloudflared" {
  name    = "cloudflared"
  image   = docker_image.cloudflared.image_id          # versión fijada
  command = ["tunnel", "--no-autoupdate", "run"]
  env     = ["TUNNEL_TOKEN=${data.cloudflare_zero_trust_tunnel_cloudflared_token.main.token}"]
  restart = "unless-stopped"
  networks_advanced { name = docker_network.edge.name }
}

module "app" {
  source       = "../modules/app"
  for_each     = local.apps
  name         = each.key
  spec         = each.value
  secrets      = try(data.sops_file.secrets[each.key].data, {})
  edge_network = docker_network.edge.name
  neon_org_id  = var.neon_org_id      # obligatorio: sin org_id Neon puede recrear proyectos
  alert_email  = var.alert_email
}
```

### Rutas del túnel y DNS

Cada servicio público recibe su hostname exacto; cualquier otro nombre responde 404. No hay DNS comodín.

```hcl
# apps/tunnel.tf
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = local.tunnel_id
  config = {
    ingress = concat(
      [for name, s in local.public_services : {
        hostname = s.hostname
        service  = "http://${name}:${s.port}"   # nombre del contenedor en la red edge
      }],
      [{ service = "http_status:404" }]
    )
  }
}

resource "cloudflare_dns_record" "svc" {
  for_each = local.public_services
  zone_id  = var.cloudflare_zone_id
  name     = each.value.hostname
  type     = "CNAME"
  content  = "${local.tunnel_id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}
```

### Módulo por app

```hcl
# modules/app/main.tf (esqueleto)
resource "docker_network" "app" { name = "app-${var.name}" }

resource "neon_project" "db" {
  count      = try(var.spec.database.neon, false) ? 1 : 0
  name       = var.name
  org_id     = var.neon_org_id
  region_id  = "aws-us-east-1"
  pg_version = 17
  lifecycle { prevent_destroy = true }   # un PR nunca puede borrar una base por accidente
}

resource "docker_image" "svc" {
  for_each = var.spec.services
  name     = each.value.image
}

resource "docker_container" "svc" {
  for_each      = var.spec.services
  name          = "${var.name}-${each.key}"
  image         = docker_image.svc[each.key].image_id
  restart       = "unless-stopped"
  memory        = each.value.memory_mb
  security_opts = ["no-new-privileges:true"]
  log_driver    = "json-file"
  log_opts      = { "max-size" = "10m", "max-file" = "3" }
  env = [for k, v in merge(
    try(each.value.env, {}),
    { for s in try(each.value.secrets, []) : s => var.secrets[s] },
    { for k, v in { DATABASE_URL = try(neon_project.db[0].connection_uri, "") } :
      k => v if try(each.value.uses_database, false) }
  ) : "${k}=${v}"]

  networks_advanced { name = docker_network.app.name }
  dynamic "networks_advanced" {
    for_each = try(each.value.public, false) ? [var.edge_network] : []
    content { name = networks_advanced.value }
  }
}

resource "digitalocean_uptime_check" "svc" {
  for_each = { for k, s in var.spec.services : k => s if try(s.public, false) }
  name     = "${var.name}-${each.key}"
  target   = "https://${each.value.hostname}${try(each.value.healthcheck, "/")}"
  regions  = ["us_east"]
}

resource "digitalocean_uptime_alert" "down" {
  for_each = digitalocean_uptime_check.svc
  name     = "${each.value.name}-caida"
  check_id = each.value.id
  type     = "down"
  period   = "2m"
  notifications { email = [var.alert_email] }
}
```

Notas:

- Los backends (`public: false`) solo están en la red de su app: ni el túnel ni las otras apps pueden llegar a ellos.
- Cambiar la imagen recrea el contenedor, con unos segundos de corte. Si más adelante necesitas cero cortes, se puede pasar a `create_before_destroy` con nombres versionados.
- Los esqueletos son el punto de partida: se validan con `tofu validate` y un primer `plan` en la fase 3.

## CI/CD y cómo no perder configuraciones

La regla central: **solo el CI aplica cambios, y solo desde `main`**. Si una configuración no está en `main`, no se despliega; por lo tanto, nunca existe una configuración desplegada que no esté guardada en Git.

| Workflow | Cuándo corre | Qué hace |
| --- | --- | --- |
| `pr.yml` | En cada pull request | `tofu fmt -check`, `validate`, tflint, escaneo de IaC con Trivy, gitleaks, verificación de que todo `secrets.enc.yaml` esté cifrado, validación de `app.yaml` contra un esquema, y `tofu plan` de ambos stacks publicado como comentario |
| `apply.yml` | Al fusionar en `main` | Se une a Tailscale como `tag:ci` (nodo efímero), corre `apply` de `platform/` y luego de `apps/`; un grupo de concurrencia impide dos ejecuciones simultáneas |
| `drift.yml` | Todos los días | `tofu plan -detailed-exitcode`; si detecta diferencias, abre un issue y te avisa |
| `backup.yml` | Todos los días | `pg_dump` de cada base Neon, cifrado con age y subido a R2 |
| Renovate | Cuando hay una imagen nueva | Abre un PR que actualiza el digest en `app.yaml` |

Protecciones contra pérdidas y errores:

- **Rama `main` protegida:** sin push directo ni force-push; requiere PR con los checks en verde.
- **Trabajo en curso a salvo:** abre el PR como borrador desde el primer commit. Tu cambio queda en GitHub (no solo en tu laptop) y el `plan` te muestra su efecto antes de terminar.
- **Hooks de pre-commit locales:** formato, gitleaks y verificación de cifrado de SOPS; un secreto en texto plano no llega ni a hacer commit.
- **Guardia contra destrucciones:** el CI analiza el plan (`tofu show -json`) y falla si va a destruir algo que no sea un contenedor, salvo que el PR tenga la etiqueta `allow-destroy`. Las bases Neon tienen además `prevent_destroy`.
- **Detección de cambios manuales:** si alguien toca el servidor o Cloudflare a mano, `drift.yml` lo detecta al día siguiente.
- **Reversión:** revertir el PR en GitHub vuelve a la configuración anterior con un nuevo `apply`.
- **Acceso de emergencia:** si GitHub Actions no está disponible, se corre `apply` desde tu equipo, conectado a Tailscale, y solo desde un commit que ya esté en `main`.

## Procedimientos: agregar, modificar y remover apps

Toda operación sigue el mismo camino: rama → PR → revisar el `plan` → fusionar. Nunca se entra al servidor a cambiar algo.

### Agregar una app

1. En el repositorio de la app, el CI construye la imagen, la escanea con Trivy, la publica en GHCR y anota su digest.
2. En `infra`, crea una rama y copia la plantilla: `cp -r catalog/_template catalog/<nombre>`.
3. Llena `app.yaml`: imagen por digest, puertos, memoria, `public` y `hostname` solo para el frontend, y `database.neon: true` si usa base de datos.
4. Si tiene secretos: `sops catalog/<nombre>/secrets.enc.yaml` y lista sus nombres en `secrets:` del servicio.
5. Abre el PR. Revisa el `plan`: debe mostrar solo creaciones (red, contenedores, proyecto Neon, ruta del túnel, registro DNS, chequeo de disponibilidad).
6. Fusiona. El CI aplica y, en un par de minutos, la app responde en su hostname.
7. Verifica que el chequeo de disponibilidad esté en verde y que los logs aparezcan en Grafana.

### Modificar una app

- **Configuración o variables:** edita `app.yaml` y abre un PR; el `plan` muestra qué contenedor se recrea.
- **Secreto:** `sops` sobre su archivo, PR y fusión. El contenedor se recrea con el valor nuevo; después revoca el valor anterior en el servicio de origen.
- **Nueva versión de la imagen:** Renovate abre el PR con el digest nuevo; lo revisas y lo fusionas. Para volver atrás, revierte ese PR.

### Remover una app

Quitar la app nunca borra su base de datos en el mismo paso; los datos se eliminan aparte y de forma deliberada.

1. Confirma que existe un backup reciente de su base en R2 (o ejecuta `backup.yml` a mano).
2. Si la app usa Neon, saca la base del estado sin borrarla: `tofu state rm 'module.app["<nombre>"].neon_project.db[0]'`. El proyecto sigue existiendo en Neon.
3. Borra la carpeta `catalog/<nombre>`, abre el PR con la etiqueta `allow-destroy` y revisa que el `plan` destruya solo lo de esa app.
4. Fusiona: desaparecen contenedores, red, ruta del túnel, registro DNS y chequeo de disponibilidad.
5. Pasado tu periodo de retención (por ejemplo, 30 días), borra el proyecto en la consola de Neon.

Retirar una app temporalmente sin borrarla: pon `enabled: false` en `app.yaml` y haz que el stack la filtre; la configuración queda en Git para volver a activarla.

## Logs, métricas y alertas

Los logs salen del servidor hacia Grafana Cloud en tiempo real, así que un atacante no puede borrar su rastro y un servidor caído no se lleva sus logs. La capa gratuita incluye 50 GB de logs, 10,000 series de métricas y 14 días de retención, y envía correos de alerta sin configurar un servidor de correo.

- **Agente:** Grafana Alloy, instalado como servicio del sistema por cloud-init y fijado a una versión. Recoge los logs de todos los contenedores (etiquetados por app y servicio), los logs del sistema y las métricas del host. Es el único componente con acceso al socket de Docker, porque lo necesita para nombrar los contenedores.
- **Alertas como código:** las reglas y los paneles de Grafana se definen con el provider de Terraform de Grafana, en el mismo repositorio.

| Señal | Herramienta | Alerta |
| --- | --- | --- |
| App pública caída o certificado por vencer | Uptime checks de DigitalOcean (uno por servicio público, creado por el módulo) | Correo a los 2 minutos de caída |
| CPU, memoria o disco del servidor | Alertas de monitoreo de DigitalOcean | Correo si pasa del umbral 10 minutos |
| Errores de una app | Grafana: líneas de error por app en 5 minutos | Correo por encima del umbral que definas |
| Contenedor reiniciándose | Grafana: eventos de reinicio | Correo si hay más de 3 en 15 minutos |
| App sin logs | Grafana: ausencia de logs | Correo tras 15 minutos de silencio |
| Túnel caído | Notificaciones de salud del túnel en Cloudflare | Correo |
| Cambios fuera de Git | `drift.yml` | Issue en GitHub y correo |
| Fallo de backup | `backup.yml` | Correo de GitHub Actions |

## Backups y recuperación

El servidor no guarda nada que no se pueda recrear: las apps son contenedores sin estado, los datos viven en Neon y los archivos que una app necesite guardar van a R2, nunca al disco del Droplet. Por eso recuperar el servidor es correr `apply`, no restaurar un disco.

| Qué | Dónde está respaldado | Retención |
| --- | --- | --- |
| Configuración y secretos cifrados | GitHub + tu clon local | Todo el historial de Git |
| Estado de OpenTofu | R2 (cifrado) + copia diaria con fecha | 30 días de copias |
| Datos de cada app | Restauración propia de Neon + `pg_dump` diario cifrado en R2 | 30 días, con regla de ciclo de vida en el bucket |
| Servidor | Backups semanales de DigitalOcean (comodidad, no la vía principal) | Los que mantiene DigitalOcean |
| Frase del estado y llave age | Tu gestor de contraseñas | Permanente |

Escenarios de recuperación:

| Si pasa esto | Se recupera así |
| --- | --- |
| El Droplet se daña o se borra | `apply` de `platform/` crea uno nuevo y `apply` de `apps/` redespliega todo; el túnel se reconecta solo |
| DigitalOcean suspende la cuenta | Cambias el recurso del servidor por el de otro proveedor (Vultr, Linode o Lightsail) y aplicas; Cloudflare, Neon y el estado no dependen de DigitalOcean |
| Se corrompen datos de una app | Restauración de Neon a un punto anterior, o el `pg_dump` del día en un proyecto nuevo |
| Se pierde el acceso a GitHub | Tu clon local tiene todo; el estado sigue en R2 |
| Se filtra un secreto | Rotarlo en el servicio de origen, actualizar con `sops`, PR y fusión |

Simulacro trimestral: restaurar un `pg_dump` en una rama de Neon y comprobar que la app arranca con esos datos, y recrear un Droplet de prueba desde cero. Un backup que nunca se restauró no es un backup.

## Checklist de seguridad

Marca cada punto al implementarlo y revísalo completo cada trimestre.

**Red y acceso**

- [ ] Cloud Firewall de DigitalOcean sin reglas de entrada
- [ ] SSH solo por Tailscale, solo con llaves, sin `root` y sin contraseñas
- [ ] ACL de Tailscale: solo tu usuario y `tag:ci` llegan al puerto 22 del servidor
- [ ] Un hostname explícito por servicio público en el túnel; todo lo demás responde 404
- [ ] Cloudflare en modo SSL Full (strict), HSTS activado y reglas de WAF y de límite de peticiones en los hostnames públicos

**Servidor y contenedores**

- [ ] `unattended-upgrades` con reinicio automático
- [ ] Docker sin socket expuesto por TCP; `daemon.json` endurecido
- [ ] Contenedores con `no-new-privileges`, límite de memoria y usuario no root en el Dockerfile
- [ ] Backends solo en la red de su app; ningún puerto publicado en el host
- [ ] Imágenes privadas en GHCR, fijadas por digest y escaneadas con Trivy en el CI de cada app

**Secretos y credenciales**

- [ ] Secretos solo en archivos SOPS; gitleaks y la verificación de cifrado en pre-commit y en CI
- [ ] Estado cifrado con `enforced = true`
- [ ] Tokens con el alcance mínimo y fecha de expiración, solo en los GitHub Environments `production` y `plan` (ADR 0011), nunca como secretos del repositorio
- [ ] Frase del estado y llave age personal en tu gestor de contraseñas
- [ ] 2FA en GitHub, DigitalOcean, Cloudflare, Neon, Tailscale y Grafana

**Proceso**

- [ ] Rama `main` protegida; `apply` solo desde el CI
- [ ] Guardia contra destrucciones en el `plan`
- [ ] Detección diaria de cambios fuera de Git
- [ ] Simulacro de restauración en el último trimestre

## Fases de implementación

Seis fases en orden; cada una termina con una condición verificable antes de pasar a la siguiente. La duración es una estimación para una persona.

1. **Cuentas y dev container** (medio día). Cuentas con 2FA, tokens en los GitHub Environments `production` y `plan` (ADR 0011), repositorio con `main` protegida y dev container funcionando.
   - Listo cuando: Claude Code corre dentro del contenedor y el hook bloquea un `tofu apply` de prueba.
2. **Base y CI** (1 día). Estado cifrado en R2, `.sops.yaml`, hooks de pre-commit, `pr.yml`, `apply.yml` y la guardia contra destrucciones. El CI va antes que el servidor porque solo el CI aplica cambios.
   - Listo cuando: un PR de prueba muestra el `plan` y un archivo de secretos sin cifrar es rechazado.
3. **Plataforma** (1 día). `platform/` con Droplet, firewall, Tailscale, túnel y alertas del servidor.
   - Listo cuando: entras por SSH solo vía Tailscale, un escaneo de puertos desde Internet no encuentra nada abierto y las alertas llegan a tu correo.
4. **Primera app** (1 a 2 días). Módulo `app`, `cloudflared`, una app de prueba y luego tu primera app real con Neon.
   - Listo cuando: la app responde en su hostname, su API no es accesible desde fuera y su chequeo de disponibilidad está en verde.
5. **Observabilidad** (1 día). Alloy y reglas de Grafana como código.
   - Listo cuando: ves los logs de la app en Grafana y una alerta de prueba llega a tu correo.
6. **Backups, drift y runbooks** (1 día). `backup.yml`, `drift.yml`, `remove-app.yml`, `destroy.yml` y los runbooks.
   - Listo cuando: completaste el primer simulacro de restauración.

Los prompts exactos de cada fase están en [docs/guia-implementacion.md](guia-implementacion.md).

## Costos, riesgos y alternativas

El costo fijo es de unos $29 al mes; todo lo demás cabe en capas gratuitas mientras las apps sean pequeñas.

| Servicio | Costo mensual aproximado |
| --- | --- |
| Droplet de 4 GB en DigitalOcean | \~$24 |
| Backups del Droplet (20 % del precio) | \~$5 |
| Neon | $0 en la capa gratuita (100 proyectos de 0.5 GB); pago por uso al crecer |
| Cloudflare (túnel, DNS, WAF básico) y R2 | $0 en capa gratuita |
| Grafana Cloud, Tailscale, GitHub | $0 en capa gratuita |

| Riesgo | Mitigación |
| --- | --- |
| Providers comunitarios (Docker, Neon, SOPS) con fallas o atrasos | Versiones fijadas, `.terraform.lock.hcl` en Git, actualizaciones por PR con Renovate |
| Un solo servidor: si cae, caen todas las apps | Reconstrucción con `apply`, alertas de disponibilidad; una app crítica puede pasar a su propio Droplet |
| Neon tarda en responder tras un periodo inactivo | Subir el timeout de conexión; desactivar la suspensión automática en las apps con clientes de pago |
| Unos segundos de corte al cambiar una imagen | Aceptable para empezar; `create_before_destroy` si hace falta |
| R2 podría no soportar el bloqueo nativo del estado | Grupo de concurrencia en el CI |
| Perder la frase del estado o la llave age | Gestor de contraseñas y una copia impresa guardada aparte |

Alternativas, si prefieres una interfaz gráfica:

- **Dokploy:** la experiencia más cómoda, pero no tiene provider de Terraform; hay uno comunitario solo para Pulumi (v0.3.1). Las apps quedarían configuradas en el panel o por su API, fuera de Git, y el panel requiere el endurecimiento de su guía oficial.
- **Coolify:** tiene un provider de Terraform con 33 recursos, así que mantiene "todo en Git" con interfaz incluida; a cambio, su panel tuvo vulnerabilidades críticas en 2026 y debe quedar solo detrás de Tailscale.

### Fuentes

- [Guía de endurecimiento para producción de Dokploy](https://docs.dokploy.com/docs/core/guides/production-hardening)
- [Dokploy con Cloudflare Tunnels](https://docs.dokploy.com/docs/core/guides/cloudflare-tunnels)
- [Provider comunitario de Dokploy para Pulumi](https://www.pulumi.com/registry/packages/dokploy/)
- [Provider de Terraform para Coolify](https://pkg.go.dev/github.com/coolify-terraform/terraform-provider-coolify@v0.1.4)
- [Neon con Terraform](https://neon.com/docs/reference/terraform)
- [Cloudflare Tunnel con Terraform](https://developers.cloudflare.com/tunnel/guides/terraform/)
- [Backend S3 de OpenTofu](https://opentofu.org/docs/language/settings/backends/s3/)
- [OpenTofu 1.10: bloqueo nativo y cifrado de estado](https://github.com/opentofu/opentofu/releases/tag/v1.10.0-beta1)
- [Alertas de monitoreo de DigitalOcean en Terraform](https://docs.digitalocean.com/reference/terraform/reference/resources/monitor_alert)
- [Uptime checks de DigitalOcean en Terraform](https://docs.digitalocean.com/reference/terraform/reference/resources/uptime_check/)
- [Uptime alerts de DigitalOcean en Terraform](https://docs.digitalocean.com/reference/terraform/reference/resources/uptime_alert)
- [Capa gratuita de Grafana Cloud](https://monitoringcost.com/grafana-cloud-pricing)
- [Precios de DigitalOcean 2026](https://www.linuxteck.com/guides/digitalocean-review-2026/)
