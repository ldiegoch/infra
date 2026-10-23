---
paths: ["catalog/**"]
---
# catalog.md
- app.yaml debe validar contra schema/app.schema.json.
- Contenedores: nombre <app>-<servicio>; memoria en MB; imágenes por digest.
- Solo servicios públicos llevan hostname; nunca comodines.
- secrets.enc.yaml debe estar cifrado antes del commit.
