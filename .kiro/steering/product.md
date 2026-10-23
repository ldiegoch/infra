# Product Overview

`infra` es el repositorio único que define, como código, un host de apps
Docker para una persona: un Droplet de DigitalOcean sin panel, con entrada
pública por Cloudflare Tunnel, bases de datos en Neon y despliegue solo desde
GitHub Actions. Agregar, cambiar o quitar una app es un pull request.

## Core Capabilities

- **Catálogo de apps en YAML**: cada app es `catalog/<app>/app.yaml` (sin
  secretos) más `secrets.enc.yaml` cifrado con SOPS + age.
- **Plataforma desechable**: el servidor se recrea con `apply`; no guarda
  nada que no se pueda reconstruir.
- **Cero puertos de entrada**: tráfico público por Cloudflare Tunnel con un
  hostname explícito por servicio; administración por Tailscale.
- **Despliegue revisado**: `plan` en cada PR, `apply` solo al fusionar en
  `main`, guardia contra destrucciones y detección diaria de drift.
- **Observabilidad y respaldo fuera del servidor**: logs y métricas en
  Grafana Cloud; estado y `pg_dump` cifrados en Cloudflare R2.

## Target Use Cases

- Publicar una app nueva (frontend público + API interna + base Neon).
- Cambiar configuración, secretos o la versión de imagen de una app.
- Pausar (`enabled: false`) o retirar una app sin perder sus datos.
- Reconstruir todo desde cero tras perder el servidor o la cuenta.
- Desarrollo asistido por agentes de IA que nunca tocan la nube.

## Value Proposition

Git es la única fuente de verdad: si no está en `main`, no está desplegado.
Costo fijo ~$29/mes (Droplet de 4 GB + backups); el resto en capas
gratuitas. Seguridad por diseño: sin panel que atacar, sin puertos abiertos
y con secretos que el agente nunca ve.

## Fuente

Detalle completo en `docs/plan.md`. Fases y prompts en
`docs/guia-implementacion.md`.

---
_Focus on patterns and purpose, not exhaustive feature lists_
