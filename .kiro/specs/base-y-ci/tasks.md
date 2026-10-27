# Implementation Plan

- [x] 1. Fundaciones: herramientas, stacks vacíos y configuración de lint
- [x] 1.1 Agregar las dependencias de validación al dev container y proponer su ADR
  - Agregar el paquete de validación de JSON Schema de la distribución y, de forma explícita, el de YAML a la instalación de paquetes del dev container
  - Redactar el ADR 0012 con estado "propuesto": contexto, decisión, alternativas descartadas (validador de PyPI, ajv, validación en OpenTofu) y consecuencias
  - Terminado cuando: el Dockerfile instala ambos paquetes y el ADR 0012 existe con la plantilla del proyecto
  - _Requirements: 4.1_

- [x] 1.2 Puerta humana: aceptar el ADR 0012 y reconstruir el dev container
  - El agente se detiene aquí y le pide al humano que acepte el ADR 0012 (constitución, principio 8) y reconstruya el dev container
  - Si el humano no lo acepta, el agente no sigue con las tareas que dependen del validador (2.2, 3.1, 3.2, 6) y vuelve al diseño
  - Terminado cuando: el ADR 0012 dice "aceptado" y, en el contenedor reconstruido, Python importa los módulos de JSON Schema y de YAML
  - _Requirements: 4.1_

- [x] 1.3 Crear los dos stacks vacíos con estado remoto cifrado
  - Crear `platform/` y `apps/`, y el README breve del directorio de módulos; los demás directorios los crean las tareas que agregan sus archivos
  - En cada stack: versión mínima de OpenTofu, backend remoto con una llave propia por stack y bloqueo activado, sin endpoint en el código
  - Cifrado obligatorio de estado y plan con una frase que llega como variable sensible, con validación de longitud mínima y sin valor por defecto
  - Ignorar en Git los artefactos de plan locales
  - No depende de la puerta 1.2: puede avanzar mientras el humano reconstruye el contenedor (igual que 1.4)
  - Si `init -backend=false` o `validate` piden la frase, detenerse y volver al diseño, sin rodearlo con un valor por defecto (rompería el requisito 2.3)
  - Terminado cuando: ambos stacks pasan `init -backend=false` y `validate` sin la variable de la frase y sin red, y no declaran recursos ni providers
  - _Requirements: 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4_

- [x] 1.4 Configurar el linter y el escaneo de IaC
  - Configurar el linter con el ruleset integrado en su preset recomendado, sin plugins descargables
  - Crear el archivo de excepciones del escáner, vacío, con una nota de que cada excepción lleva justificación
  - Si aparece el aviso de variable no usada para la frase del estado, resolverlo con una excepción justificada en línea
  - Terminado cuando: el linter recursivo y el escaneo con severidad alta y crítica terminan sin hallazgos sobre los stacks
  - _Requirements: 1.5, 9.5_

- [ ] 2. Verificaciones independientes
- [x] 2.1 (P) Reglas de cifrado del catálogo y verificación de archivos cifrados
  - Versionar la configuración de cifrado con una regla para los secretos del catálogo y las dos llaves públicas de la introducción de los requisitos
  - Verificación que, sin descifrar ni usar llaves privadas, rechaza archivos sin metadatos, valores no cifrados y destinatarios distintos de los configurados, indicando ruta y motivo sin mostrar valores
  - Códigos de salida según el contrato del diseño, incluido el caso de configuración ausente o inválida
  - Pruebas unitarias con fixtures de metadatos falsos: sin metadatos, valor en claro, destinatarios incompletos, destinatarios ajenos y archivo correcto
  - Terminado cuando: las pruebas unitarias pasan, la verificación sobre el catálogo real termina con código 0 y `gitleaks dir` sobre sus fixtures no reporta hallazgos
  - Si gitleaks reportara un fixture, crear `.gitleaksignore` con la justificación de cada entrada (esta tarea es su dueña)
  - _Boundary: .sops.yaml, check_sops.py, test_check_sops.py, fixtures/sops, .gitleaksignore_
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.7_

- [x] 2.2 (P) Esquema de app.yaml y verificación del catálogo
  - Escribir el esquema con la tabla de campos del diseño, incluidos `enabled`, la regla hostname/public y la regla `uses_database` ↔ `database.neon`
  - Verificación que valida cada `app.yaml` contra el esquema, exige nombre igual a la carpeta e ignora las carpetas que empiezan con `_`
  - Mensajes con app, ruta del campo y motivo; códigos de salida según el contrato
  - Pruebas unitarias con un caso por regla (digest, kebab-case, nombre ≠ carpeta, hostname en privado, falta de hostname en público, comodín, `uses_database` sin Neon, secretos que no son nombres), la plantilla ignorada y una app válida
  - Terminado cuando: las pruebas unitarias pasan, la verificación sobre el catálogo real termina con código 0 y `gitleaks dir` sobre sus fixtures no reporta hallazgos
  - _Boundary: app.schema.json, check_catalog.py, test_check_catalog.py, fixtures/catalog_
  - _Depends: 1.2_
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9_

- [ ] 2.3 (P) Guardia contra destrucciones con sus pruebas
  - Guardia pura que lee el plan JSON y la variable de autorización, marca destrucciones, reemplazos y `forget` de todo tipo distinto de contenedor y decide según la tabla del diseño
  - Salida con una línea por recurso afectado y un veredicto final, sin valores de atributos; los valores de autorización desconocidos se tratan como `unknown`
  - Fixtures de planes: solo creación, reemplazo de contenedor, borrado de servidor, reemplazo create-before-destroy, `forget`, JSON inválido
  - Terminado cuando: el script de pruebas cubre los casos de los requisitos 8.1 a 8.5, todos pasan sin red ni credenciales y `gitleaks dir` sobre sus fixtures no reporta hallazgos
  - _Boundary: destroy-guard.sh, test_destroy_guard.sh, fixtures/plans_
  - _Requirements: 8.1, 8.2, 8.3, 8.5, 8.6_

- [ ] 2.4 (P) Publicación del plan como comentario único por stack
  - Script que busca el comentario del PR con el marcador del stack y lo reemplaza, o lo crea si no existe
  - Incluye el resultado de la guardia y trunca los planes muy largos con un aviso
  - Prueba con un `gh` simulado en el PATH: falta de variables de entorno, creación en la primera llamada y reemplazo en la segunda
  - Terminado cuando: la prueba pasa sin red ni credenciales
  - _Boundary: pr-comment.sh, test_pr_comment.sh_
  - _Requirements: 6.2, 6.3_

- [ ] 3. Orquestación local
- [ ] 3.1 Orquestador de verificaciones con salida concisa
  - Ejecutar en orden las verificaciones del contrato del diseño: herramientas, formato, validación de stacks y módulos, lock file condicional, pruebas de OpenTofu, pruebas de scripts, linter, escaneo de IaC, detección de secretos, cifrado y catálogo
  - Descubrir las pruebas de scripts por patrón (unittest de Python y `test_*.sh`), para que las pruebas nuevas entren sin modificar el orquestador
  - Una línea por verificación exitosa; para las fallidas, solo su detalle (máximo 40 líneas); resumen final y código de salida 0 o 1
  - Ejecutar todas aunque alguna falle; una herramienta ausente cuenta como falla con su nombre
  - Terminado cuando: en el repositorio limpio todas las verificaciones dan `ok`, el código es 0 sin credenciales, y las cuatro pruebas de la tarea 2 aparecen ejecutadas
  - _Depends: 1.2, 1.4, 2.1, 2.2, 2.3, 2.4_
  - _Requirements: 1.3, 1.4, 3.6, 5.1, 5.2, 5.3, 5.4, 5.5, 9.5_

- [ ] 3.2 Hooks de pre-commit con las herramientas de la imagen
  - Hooks locales de formato, detección de secretos en los cambios en stage, cifrado de los secretos del catálogo y validación de `app.yaml`, reutilizando los mismos scripts que el orquestador
  - Ejecutar `pre-commit install` explícitamente (hoy solo corre al iniciar el contenedor)
  - Probar el rechazo con `pre-commit run --files` sobre un secreto sin cifrar temporal, sin hacer commits, y borrarlo después
  - Terminado cuando: `pre-commit run --all-files` pasa en el repositorio limpio, la prueba temporal es rechazada indicando la ruta y no quedan archivos temporales
  - _Depends: 2.1, 2.2, 3.1_
  - _Requirements: 3.4, 3.6, 4.2, 5.6_

- [ ] 4. Workflows de CI
- [ ] 4.1 Workflow reutilizable de plan y apply por stack
  - Entradas, secretos y pasos del contrato del diseño: versión de OpenTofu leída del Dockerfile, red privada con la etiqueta del CI, init, plan a archivo, salidas de texto y JSON, guardia, comentario o apply del mismo plan y limpieza final
  - Invariante: el modo apply solo con el Environment de producción y desde `main`; en otro caso falla antes del init
  - Sin `permissions` propios (hereda las del llamador); sin trazas de shell que puedan imprimir credenciales
  - Resolver por red, con `git ls-remote` sobre los repositorios oficiales, el SHA de la versión vigente de cada acción, y anotar la etiqueta como comentario; sin red, detenerse y pedirle los SHA al humano, nunca inventarlos
  - Terminado cuando: el archivo es YAML válido, todas sus acciones usan SHA de 40 caracteres resueltos con su etiqueta, y los pasos coinciden con el contrato del diseño
  - _Depends: 2.3, 2.4_
  - _Requirements: 2.3, 6.5, 6.6, 6.7, 7.3, 7.6, 7.7, 9.1, 9.3_

- [ ] 4.2 Workflow de pull request
  - Disparadores y concurrencia por PR del diseño; job de checks que construye la imagen del dev container y corre el orquestador dentro
  - Job de plan dependiente de los checks, solo para PR del mismo repositorio, en matriz por stack, con el Environment de plan y la autorización según la etiqueta del PR
  - Permisos: lectura de contenido por defecto y escritura de PR solo en el job de plan; acciones con los SHA resueltos en 4.1
  - Terminado cuando: el archivo es YAML válido y declara que el plan no corre si los checks fallan ni en forks
  - _Depends: 3.1, 4.1_
  - _Requirements: 3.5, 6.1, 6.2, 6.4, 9.1, 9.2, 9.4_

- [ ] 4.3 Workflow de apply en main
  - Disparo solo por push a `main`; concurrencia de producción sin cancelar la ejecución en curso
  - Job que resuelve la etiqueta del PR fusionado con reintentos y produce `true`, `false` o `unknown`
  - Apply de plataforma y luego de apps con el workflow reutilizable y el Environment de producción; apps depende de plataforma
  - Terminado cuando: el archivo es YAML válido, solo declara permisos de lectura de contenido y de PR, y apps no puede ejecutarse si plataforma falla
  - _Depends: 4.1_
  - _Requirements: 2.5, 7.1, 7.2, 7.4, 7.5, 8.4, 9.1, 9.2_

- [ ] 4.4 Pruebas estáticas de los workflows
  - Prueba que recorre los workflows y verifica: acciones de terceros con SHA, `permissions` en cada workflow con disparadores propios (los de solo `workflow_call` quedan exentos), apply solo en push a `main` con la concurrencia de producción sin cancelación, y plan de PR condicionado al mismo repositorio
  - El orquestador la descubre por patrón, sin cambios
  - Terminado cuando: la prueba pasa sobre los workflows reales, falla con un workflow de ejemplo que usa una etiqueta en lugar de SHA, y aparece en la salida del orquestador
  - _Depends: 4.1, 4.2, 4.3_
  - _Requirements: 7.2, 7.4, 9.1, 9.2, 9.4_

- [ ] 5. Decisión y documentación de credenciales
  - Redactar el ADR 0011 "propuesto": Environment `plan` limitado a `refs/pull/*/merge`, sin forks, credenciales de solo lectura donde se pueda, la frase del estado y la futura llave SSH como riesgo aceptado, y la falta de revisores obligatorios en Pro
  - Actualizar la tabla de credenciales del plan con el Environment de cada credencial y su alcance
  - Actualizar el Paso 1 de la guía con los dos Environments y sus reglas, los nombres de los secretos, la prueba única de bloqueo en R2 y la protección de `main`
  - Actualizar el steering técnico con los ADR 0011 y 0012, el workflow reutilizable, el validador y el bloqueo de R2 como "compatible según la documentación, pendiente de la prueba del Paso 1"
  - Terminado cuando: el ADR 0011 sigue la plantilla y los nombres de los secretos de la guía y del plan coinciden exactamente con los que usa el workflow reutilizable
  - _Depends: 4.1, 4.2, 4.3_
  - _Requirements: 10.1, 10.2, 10.3_

- [ ] 6. Validación integrada
  - Confirmar que existen todos los directorios del plan con su contenido (`platform/`, `apps/`, `modules/`, `catalog/`, `schema/`, `scripts/`, `.github/workflows/`)
  - Correr el orquestador en el repositorio limpio: todo `ok`, código 0
  - Copiar temporalmente un `app.yaml` inválido y un secreto sin cifrar al catálogo: fallan esas verificaciones, las demás corren, código 1; limpiar después
  - Correr el orquestador con un PATH sin el escáner de IaC: reporta la herramienta ausente y código 1
  - Validar ambos stacks sin la variable de la frase; correr `pre-commit run --all-files`
  - Terminado cuando: los seis resultados se observan como se describe y el repositorio queda sin archivos temporales
  - _Depends: 3.2, 4.4, 5_
  - _Requirements: 1.1, 1.3, 3.4, 4.2, 5.3, 5.4, 5.5, 5.6_

## Implementation Notes
- tflint 0.64: `--recursive` no aplica el `.tflint.hcl` de la raíz a los subdirectorios; usar siempre `--config "$PWD/.tflint.hcl"` (check.sh y CI).
- DS-0002 (Dockerfile sin `USER` no root) resuelto con `USER vscode` por decisión humana; trivy pasa sobre todo el repo.
