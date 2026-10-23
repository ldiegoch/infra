# Project Structure

## Organization Philosophy

Separación por **radio de impacto**: lo que cambia poco y afecta a todo
(`platform/`) vive aparte de lo que cambia a diario (`catalog/` → `apps/`).
Las apps son datos (YAML), no código: un módulo reutilizable las convierte
en recursos.

## Directory Patterns

### Stack de plataforma
**Location**: `/platform/`
**Purpose**: Droplet, firewall, Tailscale, túnel y alertas del host, con su
propio backend (`platform/terraform.tfstate`).
**Example**: `main.tf`, `cloud-init.yaml`, `backend.tf`

### Stack de apps
**Location**: `/apps/`
**Purpose**: raíz que lee el catálogo, `cloudflared`, red `edge`, rutas del
túnel y DNS; instancia `modules/app` con `for_each` (`apps/terraform.tfstate`).
**Example**: `main.tf`, `tunnel.tf`, `backend.tf`

### Módulo por app
**Location**: `/modules/app/`
**Purpose**: red `app-<app>`, contenedores, proyecto Neon
(`prevent_destroy`), uptime checks y alertas de una app.
**Example**: `main.tf`, `variables.tf`, `tests/*.tftest.hcl`

### Catálogo
**Location**: `/catalog/<app>/`
**Purpose**: `app.yaml` (configuración sin secretos) y `secrets.enc.yaml`
(cifrado). Carpetas que empiezan con `_` se ignoran (`_template`).
**Example**: `cp -r catalog/_template catalog/facturacion`

### Automatización y verificación
**Location**: `/.github/workflows/`, `/scripts/`, `/schema/`
**Purpose**: workflows del CI, `check.sh` y el esquema JSON de `app.yaml`.

### Documentación
**Location**: `/docs/`
**Purpose**: `plan.md` (fuente), `adr/NNNN-titulo.md` (decisiones
inmutables), `runbooks/` (procedimientos de incidentes).

## Naming Conventions

- **Recursos y código**: inglés o kebab-case sin acentos.
- **Apps**: kebab-case, igual que su carpeta (`facturacion`).
- **Contenedores**: `<app>-<servicio>` (`facturacion-api`).
- **Redes**: `edge` (cloudflared + servicios públicos), `app-<app>`.
- **ADR**: `NNNN-titulo-en-kebab-case.md`, numeración consecutiva.
- **Documentación**: español.

## Code Organization Principles

- `apps/` nunca toca `platform/` y viceversa; se comunican por salidas.
- Claves de `for_each` estables (nombre de app / servicio), nunca `count`
  para apps, para que agregar una app no reordene las demás.
- Backends (`public: false`) solo en la red de su app; ningún puerto
  publicado en el host.
- Variables con `type` y `description`; sensibles con `sensitive = true`.

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
