# 0002. Contenedores gestionados con el provider de Docker, sin panel

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Se necesita desplegar apps Docker con todo en Git. Dokploy y Coolify tuvieron vulnerabilidades críticas en 2026 y un panel es una superficie de ataque.

## Decisión
Gestionar los contenedores con `kreuzwerker/docker` vía SSH sobre Tailscale, sin panel de administración.

## Alternativas consideradas
- Dokploy: sin provider de Terraform (solo uno comunitario para Pulumi v0.3.1).
- Coolify: historial de vulnerabilidades en su panel.

## Consecuencias
No hay interfaz gráfica de despliegue; logs, métricas y alertas se ven en Grafana Cloud. Cambiar la imagen recrea el contenedor con unos segundos de corte.
