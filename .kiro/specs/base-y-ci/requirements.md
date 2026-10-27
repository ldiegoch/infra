# Requirements Document

## Project Description (Input)
**Quién tiene el problema:** el dueño del repositorio `infra`, que solo
puede aplicar cambios de infraestructura a través de GitHub Actions
(constitución, principio 2), y los agentes de IA que trabajan sin
credenciales y necesitan verificaciones locales confiables.

**Situación actual:** el repositorio tiene documentación, steering, ADR, la
configuración de agentes y `catalog/_template/app.yaml`. No existen los
stacks `platform/` y `apps/`, `scripts/check.sh`, `schema/app.schema.json`,
`.sops.yaml`, hooks de pre-commit ni workflows de CI. Sin esa base, ninguna
spec posterior puede llegar a la nube de forma segura.

**Qué debe cambiar:**
- Estructura del repositorio según `docs/plan.md`, con los stacks
  `platform/` y `apps/` todavía sin recursos, cada uno con backend `s3` en
  R2 (`use_lockfile = true`, una `key` por stack) y cifrado de estado y plan
  obligatorio (`pbkdf2` + `aes_gcm`, `enforced = true`).
- `.sops.yaml` con dos destinatarios age (las llaves públicas las da el
  humano).
- `schema/app.schema.json` que valida el formato de `app.yaml` del plan.
- Hooks de pre-commit: fmt, gitleaks, verificación de cifrado SOPS y
  validación del esquema de `app.yaml`.
- `scripts/check.sh` que corre todas las verificaciones con salida concisa.
- `pr.yml`: checks y `tofu plan` de ambos stacks comentado en el PR.
- `apply.yml`: solo en `main`, Environment `production`, Tailscale efímero
  con `tag:ci`, grupo de concurrencia y `apply` de `platform/` y luego de
  `apps/`.
- Guardia contra destrucciones: falla si el plan (`tofu show -json`) destruye
  o reemplaza algo distinto de un contenedor sin la etiqueta `allow-destroy`.

Fuera de alcance: recursos reales, crear el bucket, los tokens o el
Environment (humano), los demás workflows (`backups-y-drift`) y Renovate
(`apps`). Contexto completo en `.kiro/specs/base-y-ci/brief.md`.

## Introduction
Esta spec deja el repositorio listo para que el CI sea la única vía de
cambio hacia la nube: dos stacks vacíos con estado remoto cifrado, cifrado
obligatorio de los secretos del catálogo, validación del formato de las
apps, una verificación local que corre sin credenciales, un workflow que
muestra el plan en cada PR, otro que aplica solo desde `main` y una guardia
que detiene destrucciones no autorizadas.

Decisiones tomadas al redactar estos requisitos (2026-10-27):
- El plan de los PR obtiene credenciales de un Environment separado,
  `plan`, con tu aprobación y credenciales de solo lectura donde el
  proveedor lo permita. Nunca puede aplicar. La decisión queda registrada en
  un ADR nuevo (0011), porque el ADR 0009 y el Paso 1 limitan `production` a
  `main`.
- `.sops.yaml` se versiona con las dos llaves públicas age, como dicen el
  plan y el ADR 0006. Son públicas por diseño y SOPS las registra de todos
  modos en los metadatos de cada archivo cifrado:
  - personal: `age1rxr6aweysej7xvdcdejw9dlyp3vzp0rtmhn64rfzcn0q72z08ues62h44y`
  - CI: `age1fnuy5xuw0udwz0mggcgfuj7hy5u689dz6y46sqfvcp5svf40259qg3lxwc`

## Boundary Context
- **In scope**: estructura de directorios; configuración de estado remoto y
  su cifrado para ambos stacks (sin recursos); reglas de cifrado del
  catálogo; esquema de `app.yaml`; hooks de pre-commit; `scripts/check.sh`;
  workflows de PR y de apply; guardia contra destrucciones y sus pruebas;
  ADR 0011 y la actualización de la documentación de credenciales.
- **Out of scope**: recursos de `platform/` y `apps/`; crear el bucket
  `tofu-state`, los tokens, los Environments o la protección de `main` (lo
  hace el humano); `drift.yml`, `backup.yml`, `remove-app.yml` y
  `destroy.yml` (`backups-y-drift`); Renovate (`apps`).
- **Adjacent expectations**: el humano crea el Environment `production`
  (solo `main`) y el Environment `plan` (ramas de PR, con aprobación), y
  carga sus credenciales. Las specs posteriores agregan providers, variables
  y credenciales a los workflows sin cambiar su estructura, y pueden ampliar
  el esquema de `app.yaml`.

## Requirements

### Requirement 1: Estructura del repositorio y stacks vacíos
**Objective:** As a dueño del repositorio, I want la estructura de
directorios del plan con los dos stacks inicializados y vacíos, so that las
specs siguientes agreguen recursos sin rediseñar la base.

#### Acceptance Criteria
1. The Repositorio infra shall contener los directorios `platform/`,
   `apps/`, `modules/`, `catalog/`, `schema/`, `scripts/` y
   `.github/workflows/` con la organización descrita en `docs/plan.md` y en
   `.kiro/steering/structure.md`.
2. The Repositorio infra shall definir los stacks `platform/` y `apps/` sin
   ningún recurso gestionado, de modo que su plan no proponga cambios.
3. When se valida cada stack sin credenciales ni acceso a la red, the
   Repositorio infra shall completar la validación sin errores.
4. The Repositorio infra shall fijar la versión mínima de la herramienta de
   IaC y las versiones de cada provider usado, y guardar en Git el archivo de
   bloqueo de providers de cada stack.
5. The Repositorio infra shall declarar cada variable con tipo y
   descripción, y marcar como sensibles las que contengan secretos.

### Requirement 2: Estado remoto cifrado
**Objective:** As a dueño del repositorio, I want que el estado y los planes
de cada stack vivan fuera del servidor, separados y siempre cifrados, so
that perder el servidor o filtrar el almacenamiento no exponga secretos.

#### Acceptance Criteria
1. The Repositorio infra shall guardar el estado de `platform/` y el de
   `apps/` en el mismo almacenamiento remoto, cada uno con su propia llave.
2. The Repositorio infra shall exigir cifrado del estado y de los planes
   guardados, de modo que se rechace cualquier estado o plan sin cifrar.
3. The Repositorio infra shall recibir la frase de cifrado solo como
   variable sensible proporcionada por el CI, nunca escrita en el
   repositorio.
4. The Repositorio infra shall activar el bloqueo del estado para impedir
   dos escrituras simultáneas sobre un mismo stack.
5. If el bloqueo nativo no fuera compatible con el almacenamiento remoto,
   the Workflow de apply shall seguir impidiendo ejecuciones simultáneas
   mediante su grupo de concurrencia.

### Requirement 3: Secretos del catálogo siempre cifrados
**Objective:** As a dueño del repositorio, I want que ningún secreto llegue
a Git en texto plano, so that el repositorio pueda ser la fuente de verdad
sin exponer credenciales.

#### Acceptance Criteria
1. The Repositorio infra shall definir que todo `catalog/*/secrets.enc.yaml`
   se cifre para exactamente dos destinatarios: la llave pública personal y
   la del CI indicadas en la introducción.
2. The Repositorio infra shall versionar la configuración de cifrado con
   esas dos llaves públicas y nunca contener llaves privadas.
3. If un `secrets.enc.yaml` está cifrado para un conjunto de destinatarios
   distinto del configurado, the Verificación local shall indicarlo con la
   ruta del archivo.
4. If un `secrets.enc.yaml` no tiene los metadatos de cifrado, the
   Verificación local shall rechazar el commit e indicar la ruta del
   archivo.
5. If un `secrets.enc.yaml` no tiene los metadatos de cifrado, the Workflow
   de PR shall fallar e indicar la ruta del archivo.
6. If se detecta un secreto en cualquier archivo del repositorio, the
   Verificación local shall rechazar el commit y the Workflow de PR shall
   fallar, indicando archivo y línea sin mostrar el valor.
7. The Verificación local shall comprobar el cifrado sin descifrar ningún
   archivo ni requerir llaves privadas.

### Requirement 4: Validación del formato de las apps
**Objective:** As a dueño del repositorio, I want que cada `app.yaml` se
valide contra un esquema antes del commit y en el PR, so that los errores de
configuración se detengan antes del plan.

#### Acceptance Criteria
1. The Repositorio infra shall incluir un esquema que describa el formato de
   `app.yaml` de `docs/plan.md`, incluido el campo `enabled`.
2. If un `app.yaml` no cumple el esquema, the Verificación local shall
   rechazar el commit y the Workflow de PR shall fallar, indicando la app y
   el campo inválido.
3. If una imagen no está fijada por digest `@sha256:`, the Verificación
   local shall rechazar el `app.yaml`.
4. If el nombre de una app no está en kebab-case o no coincide con el nombre
   de su carpeta, the Verificación local shall rechazar el `app.yaml`.
5. If un servicio con `public: false` declara hostname, o un servicio con
   `public: true` no lo declara, the Verificación local shall rechazar el
   `app.yaml`.
6. If un hostname contiene un comodín, the Verificación local shall rechazar
   el `app.yaml`.
7. If un servicio declara `uses_database: true` en una app sin
   `database.neon: true`, the Verificación local shall rechazar el
   `app.yaml`.
8. If un servicio lista en `secrets` algo distinto de nombres de variables,
   the Verificación local shall rechazar el `app.yaml`.
9. The Verificación local shall ignorar las carpetas del catálogo cuyo
   nombre empieza con `_`.

### Requirement 5: Verificación local sin credenciales
**Objective:** As a dueño del repositorio o agente de IA, I want un solo
comando y hooks de pre-commit que corran todas las verificaciones sin
credenciales, so that un cambio se pueda dar por bueno antes de proponerlo.

#### Acceptance Criteria
1. The Verificación local shall ejecutar formato, validación de cada stack,
   pruebas de módulos, linter, escaneo de configuración de IaC, detección de
   secretos, verificación de cifrado del catálogo y validación del esquema de
   `app.yaml`.
2. The Verificación local shall ejecutarse sin credenciales de la nube ni
   acceso a recursos reales.
3. When todas las verificaciones pasan, the Verificación local shall mostrar
   una línea por verificación y terminar con código de salida 0.
4. If alguna verificación falla, the Verificación local shall mostrar solo
   el detalle de lo que falló, ejecutar las demás verificaciones y terminar
   con código distinto de 0.
5. If falta una herramienta requerida, the Verificación local shall fallar
   indicando cuál falta.
6. When se hace un commit, the Verificación local shall ejecutar como hooks
   de pre-commit al menos el formato, la detección de secretos, la
   verificación de cifrado y la validación del esquema.

### Requirement 6: Plan en cada pull request
**Objective:** As a dueño del repositorio, I want ver en cada PR el
resultado de las verificaciones y el plan de ambos stacks, so that pueda
revisar el efecto de un cambio antes de fusionarlo.

#### Acceptance Criteria
1. When se abre o actualiza un pull request hacia `main`, the Workflow de PR
   shall ejecutar todas las verificaciones de la Verificación local.
2. When las verificaciones pasan y el dueño aprueba el uso del Environment
   `plan`, the Workflow de PR shall generar el plan de `platform/` y de
   `apps/` y publicarlo como comentario en el PR.
3. When el PR se actualiza, the Workflow de PR shall reemplazar su
   comentario anterior en lugar de acumular comentarios nuevos.
4. If alguna verificación falla, the Workflow de PR shall marcar el PR como
   fallido y no generar el plan.
5. The Workflow de PR shall obtener credenciales solo del Environment
   `plan` y nunca ejecutar apply, destroy, import ni comandos que modifiquen
   el estado.
6. If el plan contiene valores sensibles, the Workflow de PR shall
   publicarlos ocultos.
7. The Workflow de PR shall ejecutar la Guardia contra destrucciones sobre
   cada plan y mostrar su resultado en el PR.

### Requirement 7: Apply solo desde main
**Objective:** As a dueño del repositorio, I want que los cambios se apliquen
automáticamente solo al fusionar en `main`, en orden y de uno en uno, so
that nunca exista configuración desplegada que no esté en Git.

#### Acceptance Criteria
1. When se fusiona un cambio en `main`, the Workflow de apply shall aplicar
   primero `platform/` y después `apps/`.
2. The Workflow de apply shall ejecutarse solo desde `main` y obtener
   credenciales solo del Environment `production`.
3. The Workflow de apply shall unirse a la red privada como nodo efímero con
   la etiqueta `tag:ci` y salir de ella al terminar, incluso si falla.
4. While una ejecución del Workflow de apply está en curso, the Workflow de
   apply shall poner en espera cualquier otra ejecución que toque el estado
   y nunca cancelar la que está en curso; si varias quedan en espera, se
   ejecuta solo la más reciente, que contiene los cambios de las anteriores.
5. If el apply de `platform/` falla, the Workflow de apply shall detenerse
   sin aplicar `apps/`.
6. If la Guardia contra destrucciones rechaza el plan de un stack, the
   Workflow de apply shall detenerse sin aplicar ese stack ni los
   siguientes.
7. The Workflow de apply shall aplicar exactamente el plan que evaluó la
   Guardia contra destrucciones.

### Requirement 8: Guardia contra destrucciones
**Objective:** As a dueño del repositorio, I want que el CI se detenga si un
plan destruye o reemplaza algo distinto de un contenedor sin mi
autorización explícita, so that un error no borre servidores, redes, DNS ni
datos.

#### Acceptance Criteria
1. When un plan solo crea, actualiza o destruye/reemplaza contenedores, the
   Guardia contra destrucciones shall aprobarlo.
2. If un plan destruye o reemplaza cualquier recurso que no sea un
   contenedor y el PR correspondiente no tiene la etiqueta `allow-destroy`,
   the Guardia contra destrucciones shall rechazarlo y listar cada recurso
   afectado con su acción.
3. Where el PR correspondiente tiene la etiqueta `allow-destroy`, the
   Guardia contra destrucciones shall aprobar el plan y listar los recursos
   que se destruirán o reemplazarán.
4. When se ejecuta tras una fusión en `main`, the Guardia contra
   destrucciones shall evaluar las etiquetas del PR fusionado.
5. If no se puede leer el plan, o el plan destruye o reemplaza algo
   distinto de un contenedor y no se puede determinar el PR fusionado, the
   Guardia contra destrucciones shall rechazarlo.
6. The Guardia contra destrucciones shall tener pruebas automatizadas con
   planes de ejemplo, ejecutables sin credenciales, que cubran los casos de
   1 a 5.

### Requirement 9: Seguridad de los workflows
**Objective:** As a dueño del repositorio, I want que los workflows tengan
el mínimo privilegio y no filtren credenciales, so that comprometer una
acción o un PR no dé control de la infraestructura.

#### Acceptance Criteria
1. The Repositorio infra shall fijar cada acción de terceros de los
   workflows a un SHA de commit.
2. The Repositorio infra shall declarar en cada workflow con disparadores
   propios permisos de solo lectura del contenido por defecto y ampliar
   permisos solo en el job que los necesita; los workflows reutilizables
   heredan los permisos de su llamador.
3. The Repositorio infra shall impedir que los workflows impriman
   credenciales en los registros.
4. If un pull request proviene de un fork, the Workflow de PR shall ejecutar
   solo las verificaciones sin credenciales.
5. When el escaneo de configuración de IaC encuentra un problema de
   severidad alta o crítica, the Workflow de PR shall fallar.

### Requirement 10: Decisión y documentación de credenciales
**Objective:** As a dueño del repositorio, I want que la separación de
credenciales entre el plan de los PR y el apply quede decidida y
documentada, so that sepa exactamente qué crear y dónde.

#### Acceptance Criteria
1. The Repositorio infra shall incluir el ADR 0011 que registre el uso del
   Environment `plan` para los PR, sus alternativas y sus consecuencias, con
   estado "propuesto" hasta que el humano lo acepte.
2. The Repositorio infra shall documentar, para cada Environment, qué
   credenciales contiene, con qué alcance y quién las crea.
3. The Repositorio infra shall documentar los pasos manuales que el humano
   debe completar antes del primer PR con plan: bucket del estado,
   Environments, credenciales y protección de `main`.
