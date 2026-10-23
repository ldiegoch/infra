# 0008. Observabilidad en Grafana Cloud con Alloy

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Los logs deben salir del servidor para que un atacante no borre su rastro y un servidor caído no se los lleve.

## Decisión
Grafana Alloy instalado por cloud-init, con versión fijada, enviando logs y métricas a Grafana Cloud; alertas y paneles como código con el provider de Grafana.

## Alternativas consideradas
- Logs solo en el Droplet: se pierden con el servidor.

## Consecuencias
Capa gratuita: 50 GB de logs, 10,000 series y 14 días de retención. Alloy es el único componente con acceso al socket de Docker.
