# 0011. Environment `plan` para el plan de los pull requests

- Estado: propuesto
- Fecha: 2026-10-27

## Contexto
`pr.yml` publica en cada PR el `tofu plan` de `platform` y `apps`. Para planificar, OpenTofu necesita leer el estado cifrado en R2, unirse a Tailscale y consultar a los providers, así que el job necesita credenciales. Hasta ahora todas viven en el Environment `production`, limitado a `main` (ADR 0009); un PR no puede usarlo.

Restricciones:

- El repositorio es privado y está en GitHub Pro. Pro permite Environments con reglas de rama y secretos propios en repos privados, pero no revisores obligatorios: eso exige GitHub Enterprise.
- Solo el dueño abre PR. Los PR desde forks no deben recibir credenciales (requisito 9.4).
- El estado y el plan están cifrados con `enforced = true` (ADR 0007). Planificar exige la frase del estado; no existe una frase "de solo lectura".
- Cuando la spec `apps` agregue el provider de Docker, el plan de `apps` llegará al servidor por SSH como `deploy`, que tampoco tiene una variante de solo lectura.

## Decisión
Crear un segundo Environment, `plan`, con la regla de rama `refs/pull/*/merge`. `pr.yml` llama a `_tofu-stack.yml` con `environment: plan` solo cuando el PR viene del mismo repositorio, y `apply.yml` sigue usando `production`, limitado a `main`. Los dos Environments usan los mismos nombres de secretos (hoy `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `TF_STATE_PASSPHRASE`, `TS_OAUTH_CLIENT_ID` y `TS_OAUTH_SECRET`); en `plan` cada credencial se crea aparte y es de solo lectura donde el proveedor lo permita; las que no tienen esa variante llevan el mismo alcance que en `production`.

## Alternativas consideradas
- Sin plan en los PR: el humano fusionaría sin ver el efecto del cambio y la guardia contra destrucciones solo actuaría en el apply. Contradice el flujo del plan (docs/plan.md, "CI/CD").
- Usar `production` desde los PR: obliga a quitar la regla de rama de `production`, y cualquier rama podría correr `apply` con credenciales de escritura.
- Secretos a nivel de repositorio: los ve cualquier workflow de cualquier rama, sin regla de rama ni separación entre plan y apply.
- Revisores obligatorios en `plan` o en `production`: no disponibles en repos privados con GitHub Pro.
- `pull_request_target`: correría con secretos sobre código del PR, el patrón más expuesto de GitHub Actions.

## Consecuencias
- Mejora: cada PR muestra su plan y la guardia antes de fusionar, y las credenciales de escritura de los proveedores quedan solo en `production`.
- Sin forks: el job de plan exige que la rama del PR viva en este repositorio, y la regla `refs/pull/*/merge` impide usar `plan` desde un push a otra rama.
- Solo lectura donde se pueda: en `plan` se crean credenciales propias (por ejemplo, un cliente OAuth de Tailscale que solo crea llaves con `tag:ci` y lee la política). La llave de R2 de `plan` necesita lectura y escritura sobre `tofu-state`, porque el plan toma el bloqueo del estado (`use_lockfile`).
- Riesgo aceptado: `plan` contiene secretos que dan el mismo acceso que en `production`: la frase del estado (descifra el estado completo) y la futura llave SSH de `deploy` para el plan de `apps`. Quien pueda abrir un PR en este repositorio puede leerlos sin tocar el workflow: basta con cambiar código `.tf` en su rama (un data source o un provider), porque el plan ejecuta el código del PR con esas credenciales. Se acepta porque el repositorio es privado, solo el dueño abre PR y los forks quedan excluidos. Si se suman colaboradores con escritura, hay que revisar esta decisión.
- Pendiente de decisión humana al aceptar este ADR (o en la spec `apps`): la llave age del CI y cualquier llave de proveedor sin variante de solo lectura (por ejemplo, la de Neon). El plan de `apps` leerá el catálogo con `data "sops_file"`, que descifra en tiempo de plan, así que `plan` necesitaría la misma llave que `production`. La spec `apps` puede revisarlo: aceptarlo como riesgo o buscar otra forma de planificar sin descifrar.
- Riesgo aceptado: `apply.yml` lee la etiqueta `allow-destroy` del PR fusionado al aplicar, no al fusionar. Quien tenga escritura podría ponerla después del merge y antes de que corra el apply. Se acepta con un solo dueño; con más colaboradores habría que fijar la etiqueta en el momento del merge.
- Limitación de GitHub Pro: sin revisores obligatorios, nada exige una segunda persona antes de que un PR use `plan` o de que `main` use `production`. La protección es la de `main`: PR obligatorio, checks en verde y sin force-push. Como `main` está protegida, un PR no puede cambiar `apply.yml` sin pasar por la fusión.
- Hay que vigilar: las credenciales de `plan` se rotan junto con las de `production`, y cada spec que agregue un secreto lo crea en ambos Environments con el mismo nombre.
- Al aceptar este ADR, el humano debe actualizar la regla "Credenciales solo desde el Environment production" de `.claude/rules/workflows.md` para admitir el Environment `plan` en el plan de los PR; el agente no edita `.claude/`.
