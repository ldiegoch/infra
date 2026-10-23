# 0010. Agentes de IA sin credenciales, en un dev container

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Claude Code escribe el código; un error o una instrucción maliciosa no debe poder tocar la nube.

## Decisión
Los agentes trabajan en un dev container sin credenciales de producción, con permisos y un hook que bloquean comandos peligrosos.

## Alternativas consideradas
- Herramientas instaladas en la computadora local: el agente tendría acceso a credenciales y archivos del equipo.

## Consecuencias
Tres capas independientes: instrucciones, contrato (permisos + hook) y aislamiento. El agente solo valida con providers simulados; el humano edita los secretos en una terminal aparte.
