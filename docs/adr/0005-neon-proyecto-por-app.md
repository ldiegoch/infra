# 0005. Neon, un proyecto por app

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Las apps necesitan Postgres con aislamiento y credenciales propias, y el servidor no debe guardar datos.

## Decisión
Un proyecto Neon por app (`kislerdm/neon`), con `org_id` obligatorio y `prevent_destroy`.

## Alternativas consideradas
- Postgres en el Droplet: el servidor dejaría de ser desechable.
- Un cluster compartido: sin aislamiento ni credenciales por app.

## Consecuencias
Neon puede tardar en responder tras inactividad. Quitar una app nunca borra su base en el mismo cambio.
