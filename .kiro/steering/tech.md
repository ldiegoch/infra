# Technology Stack

## Architecture

Dos stacks de OpenTofu con estados separados, para que un error en una app
nunca toque la red o el servidor:

- `platform/`: Droplet, Cloud Firewall sin entrada, llave y ACL de
  Tailscale, túnel de Cloudflare, alertas del host. Cambia poco.
- `apps/`: lee `catalog/*/app.yaml` y, por app, crea red, contenedores,
  proyecto Neon, rutas del túnel, DNS y uptime checks vía `modules/app`.

`apps/` consume las salidas de `platform/` (nombre en Tailscale `apps-1`,
ID del túnel, ID del Droplet). El provider de Docker llega al servidor por
`ssh://deploy@apps-1:22` sobre Tailscale.

## Core Technologies

- **IaC**: OpenTofu ≥ 1.10 (dev container: 1.12.x), HCL.
- **Host**: Droplet Ubuntu 24.04, `s-2vcpu-4gb`, `nyc3`, cloud-init endurecido.
- **Runtime**: Docker Engine (`live-restore`, sin `userland-proxy`, logs 10 MB × 3).
- **CI/CD**: GitHub Actions (`pr.yml`, `apply.yml`, `drift.yml`,
  `backup.yml`, `remove-app.yml`, `destroy.yml`) + Renovate.

## Providers

`digitalocean/digitalocean`, `cloudflare/cloudflare` (recursos v5:
`cloudflare_dns_record`, `cloudflare_zero_trust_tunnel_cloudflared*`),
`tailscale/tailscale`, `kreuzwerker/docker`, `kislerdm/neon`,
`carlpett/sops`, `grafana/grafana`. Versiones fijadas en `required_providers`
y `.terraform.lock.hcl` en Git. Cualquier provider nuevo requiere ADR.

## Estado y secretos

- Backend `s3` en R2 (`tofu-state`), una `key` por stack,
  `use_lockfile = true`, cifrado `pbkdf2` + `aes_gcm` con `enforced = true`
  para estado y plan. La frase llega del CI (`var.state_passphrase`).
- Pendiente de verificar: si R2 acepta las escrituras condicionales de
  `use_lockfile`. Si no, basta el grupo de concurrencia `tofu-production`.
- Secretos de apps: SOPS + age (dos destinatarios: humano y CI), leídos
  con `data "sops_file"`. Lo generable (URL de Neon, token del túnel) lo
  genera OpenTofu y lo inyecta al contenedor.

## Development Standards

### Calidad
`scripts/check.sh` agrupa: `tofu fmt -check`, `tofu validate` por stack
(`init -backend=false`), `tofu test`, `tflint`, `trivy config`, `gitleaks`,
verificación de cifrado SOPS y validación de `app.yaml` contra
`schema/app.schema.json`. Su salida debe ser concisa: una línea por
verificación en éxito y el detalle solo de lo que falla.

### Testing
`tofu test` con `mock_provider` para la lógica de módulos; nunca contra
recursos reales. El agente no tiene credenciales: lo único que puede
probar es lo que corre sin red hacia la nube.

### Seguridad en CI
Acciones fijadas por SHA, `permissions: contents: read` por defecto,
credenciales solo del Environment `production`, guardia que falla si el
plan (`tofu show -json`) destruye algo distinto de un contenedor sin la
etiqueta `allow-destroy`.

## Development Environment

### Required Tools
Dev container (`.devcontainer/`): OpenTofu, SOPS, age, tflint, Trivy,
gitleaks, pre-commit, jq, Node LTS (cc-sdd), GitHub CLI y Claude Code.
Versiones fijadas como `ARG` del Dockerfile y verificadas por checksum.

### Common Commands
```bash
# Todo:     ./scripts/check.sh
# Validar:  tofu -chdir=apps init -backend=false && tofu -chdir=apps validate
# Pruebas:  tofu -chdir=modules/app test
# Hook:     bash .claude/hooks/guard.test.sh
```

## Key Technical Decisions

Registradas en `docs/adr/0001`–`0010`: OpenTofu, provider Docker sin panel,
Droplet de DigitalOcean, entrada solo por Tunnel, Neon por app, SOPS + age,
estado en R2, Grafana Cloud + Alloy, solo el CI aplica, agentes sin
credenciales.

---
_Document standards and patterns, not every dependency_
