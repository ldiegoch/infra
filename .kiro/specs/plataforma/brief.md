# Brief: plataforma

## Problem
Las apps necesitan un servidor seguro y desechable, sin panel y sin puertos
de entrada, que se pueda recrear con un `apply`.

## Current State
`platform/` existe vacío, con backend y cifrado (spec `base-y-ci`). No hay
servidor, red privada ni túnel.

## Desired Outcome
Según `docs/plan.md` § "Stack de plataforma":
- Droplet `apps-1` (Ubuntu 24.04, `s-2vcpu-4gb`, `nyc3`), con backups
  semanales y monitoreo, y `ignore_changes = [user_data]`.
- `cloud-init.yaml` endurecido: usuario `deploy` (grupo `docker`) solo con
  llave, sin root ni contraseñas, `unattended-upgrades`, Docker con
  `daemon.json` (`live-restore`, sin `userland-proxy`, logs 10 MB × 3),
  Tailscale con llave de un solo uso y fail2ban.
- Cloud Firewall sin reglas de entrada.
- `tailscale_tailnet_key` de un solo uso con `tag:server` y ACL que solo
  permite a `tag:ci` y al humano llegar al puerto 22 del servidor.
- Túnel de Cloudflare `apps-1` con `config_src = "cloudflare"` (sin rutas).
- Alertas de CPU, memoria y disco por correo.
- Salidas para `apps/`: nombre en Tailscale, ID del túnel, ID del Droplet.

## Approach
El esqueleto HCL del plan. `tofu test` con `mock_provider` verifica las
invariantes de seguridad: que el firewall no tenga `inbound_rule`, que la
llave no sea reutilizable, que existan las tres alertas y que el
`user_data` renderizado contenga el endurecimiento.

## Scope
- **In**: recursos de `platform/`, `cloud-init.yaml`, variables (tipadas,
  sensibles donde corresponde), salidas, pruebas y la integración de sus
  providers y variables en `pr.yml`/`apply.yml`.
- **Out**: rutas del túnel, DNS, `cloudflared` y contenedores (spec `apps`);
  Alloy y Grafana (spec `observabilidad`).

## Boundary Candidates
- Servidor y cloud-init.
- Red privada (Tailscale: llave + ACL) y firewall.
- Túnel (solo el recurso y su token).
- Alertas del host.

## Out of Boundary
- Cualquier recurso que dependa de las apps.

## Upstream / Downstream
- **Upstream**: `base-y-ci`; ADR 0002, 0003, 0004.
- **Downstream**: `apps` lee las salidas; `observabilidad` amplía
  `cloud-init.yaml` y agrega recursos de Grafana en este stack.

## Existing Spec Touchpoints
- **Extends**: `base-y-ci` (workflows: variables y secretos del stack).
- **Adjacent**: `apps`, `observabilidad`.

## Constraints
- `tailscale_acl` reemplaza la política completa del tailnet: el diseño debe
  dejarlo explícito.
- La llave del servidor viaja en `user_data`; el estado está cifrado, pero el
  diseño debe minimizar su vigencia (`expiry`).
- Puerta en la nube (humano): SSH solo vía Tailscale, escaneo de puertos sin
  nada abierto y alertas de prueba en el correo.
