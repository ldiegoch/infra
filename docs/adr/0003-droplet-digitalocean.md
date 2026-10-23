# 0003. Un Droplet de DigitalOcean como host

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Las apps son pequeñas y caben en un solo servidor. Neon está en `aws-us-east-1`.

## Decisión
Un Droplet Ubuntu 24.04 de 4 GB (`s-2vcpu-4gb`) en `nyc3`, con backups semanales y monitoreo; se amplía a 8 GB cuando crezca.

## Alternativas consideradas
- Hetzner: riesgo de bloqueo de cuenta.
- Render: costo por servicio.

## Consecuencias
Un solo servidor: si cae, caen todas las apps. Se trata como desechable y se recrea con `apply`. Si DigitalOcean suspende la cuenta, se cambia el recurso del servidor por otro proveedor.
