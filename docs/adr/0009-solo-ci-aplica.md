# 0009. Solo GitHub Actions aplica y destruye

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Ninguna configuración desplegada debe existir fuera de Git.

## Decisión
Solo GitHub Actions ejecuta `apply` y `destroy`, solo desde `main`, con el Environment `production` y un grupo de concurrencia.

## Alternativas consideradas
- Aplicar desde la computadora del desarrollador: configuraciones sin guardar en Git.

## Consecuencias
`main` protegida, plan en cada PR y guardia contra destrucciones. Acceso de emergencia: `apply` desde tu equipo por Tailscale, solo desde un commit en `main`.
