# Brief: apps

## Problem
Publicar, cambiar, pausar o retirar una app debe ser un PR que edita un YAML,
sin tocar la red ni el servidor y sin perder datos.

## Current State
Existen `apps/` vacío con backend (`base-y-ci`), `schema/app.schema.json`,
`catalog/_template/app.yaml` y las salidas de `platform/` (túnel, servidor).

## Desired Outcome
Según `docs/plan.md` § "Stack de apps" y § "Procedimientos":
- `apps/` lee `catalog/*/app.yaml` (ignora carpetas que empiezan con `_`),
  filtra por `enabled` y lee las salidas de `platform/`.
- Provider Docker por `ssh://deploy@apps-1:22` sobre Tailscale.
- `cloudflared` con el token del túnel, red `edge`, configuración de rutas
  del túnel con un hostname explícito por servicio público y un 404 final, y
  registros DNS por hostname (sin comodín).
- `modules/app` con `for_each` por app: red `app-<app>`, contenedores
  `<app>-<servicio>` por digest sin puertos publicados (públicos en `edge` y
  en su red; backends solo en su red), etiquetas `app`/`service`, secretos
  desde `sops_file`, proyecto Neon con `prevent_destroy` y URL inyectada, y
  uptime checks por servicio público.
- App de prueba `catalog/hola` con nginx por digest.
- Configuración de Renovate que actualiza digests en `app.yaml`.

## Approach
La del plan. `tofu test` del módulo con `mock_provider` cubre: que los
backends no estén en `edge`, que no se publiquen puertos, que Neon tenga
`prevent_destroy`, que `enabled: false` no cree contenedores y conserve la
base, que las claves de `for_each` sean estables y que se rechacen imágenes
sin digest.

## Scope
- **In**: `apps/`, `modules/app/` con pruebas, `catalog/hola/`, ajustes al
  esquema, `renovate.json` e integración de sus providers en los workflows.
- **Out**: apps reales; Alloy y reglas de Grafana (`observabilidad`);
  `remove-app.yml` y backups (`backups-y-drift`).

## Boundary Candidates
- Lectura y validación del catálogo.
- Entrada (cloudflared, rutas del túnel, DNS).
- Módulo por app (redes, contenedores, Neon, uptime).
- Actualización de imágenes (Renovate).

## Out of Boundary
- Recursos de `platform/`; nunca se escriben desde `apps/`.

## Upstream / Downstream
- **Upstream**: `base-y-ci`, `plataforma`; ADR 0002, 0004, 0005, 0006.
- **Downstream**: `observabilidad` usa las etiquetas de los contenedores;
  `backups-y-drift` usa las bases Neon y el procedimiento de retiro.

## Existing Spec Touchpoints
- **Extends**: `base-y-ci` (esquema y workflows).
- **Adjacent**: `plataforma` (contrato de salidas), `observabilidad`.

## Constraints
- Renovate está en el plan (tech.md); no requiere ADR, pero tampoco agrega
  otros bots.
- Quitar una app nunca destruye su base en el mismo cambio (principio 6).
- Puerta en la nube (humano): `hola` responde en su hostname, un hostname no
  declarado devuelve 404 y el uptime check está en verde.
