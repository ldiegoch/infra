# Brief: observabilidad

## Problem
Sin logs fuera del servidor, un servidor caído o comprometido se lleva su
rastro, y nadie se entera de errores, reinicios o silencios de una app.

## Current State
Hay alertas de host de DigitalOcean (`plataforma`) y uptime checks por
servicio público (`apps`). No hay logs centralizados, alertas de Grafana ni
avisos del túnel.

## Desired Outcome
Según `docs/plan.md` § "Logs, métricas y alertas":
- Grafana Alloy instalado por `cloud-init.yaml`, fijado a una versión, que
  envía a Grafana Cloud los logs de contenedores (etiquetados por `app` y
  `service`), los logs del sistema y las métricas del host. Es el único
  componente con acceso al socket de Docker.
- En `platform/`, con el provider `grafana/grafana`: punto de contacto por
  correo y reglas genéricas agrupadas por `app` para errores en 5 minutos,
  más de 3 reinicios en 15 minutos y 15 minutos sin logs, más los paneles.
- Aviso de salud del túnel de Cloudflare por correo.

## Approach
Decidido en el discovery (2026-10-23): todo Grafana como código en
`platform/`, con reglas genéricas por etiqueta y sin recursos por app. Alloy
se agrega a `cloud-init.yaml`; por `ignore_changes = [user_data]` se aplica
recreando el Droplet, con la etiqueta `allow-destroy` y la explicación en el
PR. Las pruebas con `mock_provider` verifican las reglas y que el
`user_data` incluya Alloy con su versión fija.

## Scope
- **In**: cambios a `cloud-init.yaml`, recursos de Grafana y de avisos del
  túnel en `platform/`, variables nuevas, pruebas, y actualización de la
  tabla de credenciales del plan y de los workflows.
- **Out**: uptime checks y alertas de host (ya existen); alertas de drift y
  de backup (`backups-y-drift`).

## Boundary Candidates
- Recolección (Alloy en cloud-init).
- Alertas y paneles de Grafana como código.
- Avisos del túnel en Cloudflare.

## Out of Boundary
- Métricas de aplicación propias de cada app.
- Un tercer stack de OpenTofu (descartado).

## Upstream / Downstream
- **Upstream**: `plataforma` (cloud-init, stack), `apps` (etiquetas de los
  contenedores); ADR 0008.
- **Downstream**: los runbooks de `backups-y-drift` remiten a estas alertas.

## Existing Spec Touchpoints
- **Extends**: `plataforma` (cloud-init y recursos del stack), `base-y-ci`
  (variables y secretos en los workflows).
- **Adjacent**: `apps`.

## Constraints
- Credenciales que faltan en la tabla del plan: token de escritura de Alloy
  hacia Grafana Cloud y token del provider de Grafana. Las crea el humano en
  el Environment `production`.
- El token de Alloy viaja en `user_data`: el diseño debe justificar su
  alcance mínimo (solo escritura).
- Verificar que el aviso del túnel use recursos de Cloudflare ya cubiertos
  por el provider actual y que el token tenga el permiso; si no, ADR o
  pedido al humano.
- Puerta en la nube (humano): se ven los logs de `hola` en Grafana y una
  alerta de prueba llega al correo.
