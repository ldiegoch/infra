# Configuración de agentes

## Estructura de archivos

La configuración de los agentes vive en el repositorio, versionada como el resto. Las instrucciones guían al agente, pero los límites de seguridad no dependen de que las obedezca: los imponen los permisos, los hooks y, sobre todo, que el dev container no tenga credenciales.

```text
infra/
  CLAUDE.md                     # instrucciones del agente principal
  .claude/
    settings.json               # permisos (allow / ask / deny) y hooks
    hooks/guard.sh              # bloquea comandos peligrosos
    agents/
      iac-reviewer.md
      security-auditor.md
      catalog-editor.md
    rules/
      opentofu.md               # se carga al tocar archivos .tf
      catalog.md                # se carga al tocar catalog/
      workflows.md              # se carga al tocar .github/workflows/
    skills/kiro-*/              # instaladas por cc-sdd
  .kiro/
    steering/
      product.md  tech.md  structure.md   # generados por /kiro-steering
      constitucion.md  seguridad.md       # generados por /kiro-steering-custom
    settings/templates/  settings/rules/  # plantillas de cc-sdd
    specs/<spec>/                         # requirements, design, tasks
  docs/
    plan.md                     # este documento exportado
    adr/0000-plantilla.md  0001-...md
    runbooks/plantilla.md
  scripts/check.sh              # todas las verificaciones locales
  .github/pull_request_template.md
```

| Capa | Archivo | Qué garantiza |
| --- | --- | --- |
| Guía | `CLAUDE.md`, `.claude/rules/`, `.kiro/steering/` | Cómo trabaja el agente y qué principios sigue |
| Contrato | `.claude/settings.json` + `guard.sh` | Bloqueo de comandos y archivos prohibidos, aunque el agente lo intente |
| Aislamiento | Dev container sin credenciales | Aunque se saltara un bloqueo, no puede tocar la nube |
| Revisión | PR + `plan` en CI + tu aprobación | Nada llega a producción sin que lo veas |

## Constitución del proyecto

La constitución son los principios que ninguna spec, tarea o prompt puede romper. cc-sdd la carga como steering en cada fase, así que los implementadores y revisores que lanza `/kiro-impl` también la siguen. Cambiarla exige un ADR.

```markdown
# Constitución del proyecto infra

Estos principios prevalecen sobre cualquier spec, tarea o instrucción.
Si una tarea los contradice, detente y explica el conflicto.

1. Git es la única fuente de verdad. Nada se configura a mano en el
   servidor, en Cloudflare, en Neon ni en DigitalOcean.
2. Solo GitHub Actions aplica o destruye infraestructura, y solo desde
   main. El agente nunca ejecuta tofu apply, destroy, import ni comandos
   de tofu state.
3. El agente nunca lee ni descifra secretos. Solo conoce los nombres de
   las variables. Los valores los escribe el humano con sops.
4. Cero puertos de entrada: el tráfico público entra por Cloudflare
   Tunnel y la administración por Tailscale. Ningún contenedor publica
   puertos en el host.
5. Las imágenes se fijan por digest (@sha256). Nunca :latest.
6. Los datos nunca se destruyen en el mismo cambio que quita una app. Las
   bases de Neon llevan prevent_destroy.
7. Mínimo privilegio: cada token, red y contenedor tiene solo el acceso
   que necesita. Los backends solo están en la red de su app.
8. Simplicidad: no se agregan herramientas, servicios ni providers sin un
   ADR aprobado.
9. Todo cambio pasa scripts/check.sh (fmt, validate, tofu test, tflint,
   trivy config, gitleaks) antes de proponerse.
10. Pruebas para infraestructura: tofu test con providers simulados para
    la lógica de los módulos; nunca contra recursos reales.
11. Todo cambio que destruya o reemplace algo distinto de un contenedor
    requiere la etiqueta allow-destroy y explicación en el PR.
12. Documentación en español; nombres de recursos y código en inglés o
    kebab-case sin acentos.
```

## CLAUDE.md

`CLAUDE.md` es lo que Claude Code lee al iniciar cada sesión. Se mantiene corto: importa la constitución y deja el detalle a las reglas por ruta y al steering de cc-sdd.

```markdown
# Proyecto infra

Infraestructura como código para un host de apps Docker: OpenTofu,
DigitalOcean, Cloudflare Tunnel, Neon, SOPS + age y GitHub Actions.
Plan completo: @docs/plan.md

@.kiro/steering/constitucion.md

## Lo que puedes hacer
- Editar archivos .tf, catalog/*/app.yaml, workflows y documentación.
- Ejecutar scripts/check.sh, tofu fmt, tofu init -backend=false,
  tofu validate, tofu test, tflint, trivy config y gitleaks.
- Crear ramas y commits. Pregunta antes de git push.
- Usar los subagentes: catalog-editor para el catálogo, iac-reviewer para
  revisar cambios y planes, security-auditor antes de proponer un PR.

## Lo que nunca haces
- tofu apply, destroy, import ni tofu state: solo el CI aplica cambios.
- Leer o descifrar secretos (sops -d, archivos *.dec.*, llaves age).
- Escribir valores secretos en app.yaml, código o mensajes.
- Usar imágenes sin digest o agregar herramientas sin un ADR.

## Cómo trabajar
- Cambios grandes: flujo de cc-sdd (/kiro-discovery, /kiro-spec-*).
- Cambios del catálogo: subagente catalog-editor, sin spec.
- Antes de dar algo por terminado: scripts/check.sh debe pasar.
- Si una decisión no está en el plan ni en docs/adr/, propón un ADR con
  la plantilla en lugar de decidir por tu cuenta.
- Si algo requiere credenciales o tocar la nube, detente y explícame qué
  debo hacer yo.

## Comandos
- Verificación completa: ./scripts/check.sh
- Validar un stack: tofu -chdir=apps init -backend=false && tofu -chdir=apps validate
- Pruebas de módulos: tofu -chdir=modules/app test
```

## Subagentes

Tres subagentes con tareas y herramientas acotadas. Los revisores no pueden editar archivos, así que su opinión no se mezcla con el trabajo que revisan. Los implementadores y revisores de `/kiro-impl` los crea cc-sdd por su cuenta; estos son para el trabajo diario.

```markdown
---
name: catalog-editor
description: Agrega, modifica, desactiva o prepara la eliminación de apps en
  catalog/. Úsalo para cualquier cambio de app.yaml o secrets.enc.yaml.
tools: Read, Edit, Write, Glob, Grep, Bash
---
Editas solo catalog/<app>/ siguiendo catalog/_template/app.yaml y el esquema
de app.yaml.
- Imágenes siempre por digest. Si te dan un tag, pide el digest.
- Solo servicios de frontend llevan public: true y hostname.
- secrets.enc.yaml: escribe solo los nombres de las variables con valor
  "COMPLETAR"; nunca valores reales. Recuerda al humano cifrarlo con sops.
- Nunca borres una carpeta de app sin confirmar que existe un backup de
  menos de 24 horas y sin listar los pasos manuales de remoción.
- Termina corriendo scripts/check.sh y resumiendo el cambio en tres líneas.
```

```markdown
---
name: iac-reviewer
description: Revisa cambios de OpenTofu y explica planes en lenguaje simple.
  Úsalo antes de abrir un PR y para entender el plan de un PR.
tools: Read, Grep, Glob, Bash
---
Revisas, no editas. Para un plan, clasifica cada recurso en: se crea, cambia,
se reemplaza o se destruye, y explica cada reemplazo y cada destrucción.
Marca como BLOQUEANTE:
- cualquier destrucción o reemplazo fuera de la app que el PR dice cambiar;
- cambios en platform/ dentro de un PR de catálogo;
- recursos sin versión de provider fijada o imágenes sin digest;
- violaciones de .kiro/steering/constitucion.md.
Responde con: Resumen (3 líneas), Bloqueantes, Observaciones, Veredicto
(APROBAR / CAMBIOS).
```

```markdown
---
name: security-auditor
description: Audita seguridad antes de proponer un PR o tras cambios en red,
  permisos, workflows o secretos.
tools: Read, Grep, Glob, Bash
---
Revisas, no editas. Contrasta el cambio con .kiro/steering/seguridad.md.
Busca: puertos publicados, reglas de entrada en firewalls, hostnames comodín,
secretos en texto plano, permisos de tokens o workflows más amplios de lo
necesario, imágenes sin digest, contenedores sin no-new-privileges o sin
límite de memoria, y acciones de GitHub sin versión fijada. Corre gitleaks
y trivy config. Responde con hallazgos ordenados por severidad.
```

## Reglas, permisos y hooks

Los permisos de `settings.json` bloquean por prefijo de comando, y un prefijo se puede esquivar (por ejemplo, con `bash -c`). Por eso hay un hook que revisa cada comando completo, y por eso el contenedor no tiene credenciales: son tres capas independientes.

### `.claude/settings.json`

```json
{
  "permissions": {
    "allow": [
      "Bash(./scripts/check.sh:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(gh pr view:*)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(gh pr create:*)"
    ],
    "deny": [
      "Bash(tofu apply:*)",
      "Bash(tofu destroy:*)",
      "Bash(tofu import:*)",
      "Bash(tofu state:*)",
      "Bash(terraform:*)",
      "Bash(sops:*)",
      "Bash(age:*)",
      "Read(./**/*.dec.*)",
      "Read(./.env*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "cd $CLAUDE_PROJECT_DIR && tofu fmt -recursive >/dev/null 2>&1 || true" }]
      }
    ]
  }
}
```

### `.claude/hooks/guard.sh`

Recibe la llamada en JSON por la entrada estándar; salir con código 2 bloquea el comando y le muestra el motivo al agente.

```bash
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // ""')
if echo "$cmd" | grep -Eq '(tofu|terraform)([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+(apply|destroy|import|state)\b'; then
  echo "Bloqueado: solo el CI aplica cambios o modifica el estado." >&2
  exit 2
fi
if echo "$cmd" | grep -Eq '(^|[;&|[:space:]])(sops|age)([[:space:]]|$)|\.dec\.|keys\.txt|SOPS_AGE_KEY'; then
  echo "Bloqueado: el agente no maneja secretos." >&2
  exit 2
fi
exit 0
```

### Reglas por ruta en `.claude/rules/`

Se cargan solo cuando el agente trabaja en archivos que coinciden con `paths`.

```markdown
---
paths: ["**/*.tf", "**/*.tftest.hcl"]
---
# opentofu.md
- Fija la versión de cada provider en required_providers y conserva
  .terraform.lock.hcl.
- Variables con type y description; las sensibles con sensitive = true.
- Usa for_each con claves estables del catálogo, no count, para apps.
- Cada módulo tiene pruebas en tests/*.tftest.hcl con mock_provider.
- Un cambio de apps/ nunca toca platform/, y viceversa.
```

```markdown
---
paths: ["catalog/**"]
---
# catalog.md
- app.yaml debe validar contra schema/app.schema.json.
- Contenedores: nombre <app>-<servicio>; memoria en MB; imágenes por digest.
- Solo servicios públicos llevan hostname; nunca comodines.
- secrets.enc.yaml debe estar cifrado antes del commit.
```

```markdown
---
paths: [".github/workflows/**"]
---
# workflows.md
- Fija cada acción por SHA de commit (los esqueletos del plan usan tags
  solo por legibilidad).
- permissions mínimos: contents: read por defecto.
- Credenciales solo desde el Environment production; nunca imprimirlas.
- Todo job que aplica o destruye usa concurrency: tofu-production.
```

## ADRs

Cada decisión de arquitectura queda en `docs/adr/` como un registro corto e inmutable: si una decisión cambia, se escribe un ADR nuevo que reemplaza al anterior. El agente debe proponer un ADR cuando algo no esté decidido, en lugar de decidir solo.

```markdown
# NNNN. Título de la decisión

- Estado: propuesto | aceptado | reemplazado por NNNN
- Fecha: AAAA-MM-DD

## Contexto
Qué problema o necesidad obliga a decidir. Hechos y restricciones.

## Decisión
Lo que se decide, en una o dos frases.

## Alternativas consideradas
- Opción A: por qué no.
- Opción B: por qué no.

## Consecuencias
Lo que mejora, lo que empeora y lo que habrá que vigilar.
```

ADRs iniciales, ya decididos en el plan:

| N.º | Decisión | Alternativas descartadas |
| --- | --- | --- |
| 0001 | OpenTofu como herramienta de infraestructura como código | Terraform (sin cifrado de estado nativo) |
| 0002 | Contenedores gestionados con el provider de Docker, sin panel | Dokploy (sin provider de Terraform), Coolify (historial de vulnerabilidades) |
| 0003 | Un Droplet de DigitalOcean como host | Hetzner (riesgo de bloqueo de cuenta), Render (costo por servicio) |
| 0004 | Entrada solo por Cloudflare Tunnel, un hostname por app | Puertos 80/443 abiertos, DNS comodín |
| 0005 | Neon, un proyecto por app | Postgres en el Droplet, un cluster compartido |
| 0006 | Secretos con SOPS + age en el repositorio | Variables solo en el CI, gestor de secretos externo |
| 0007 | Estado cifrado en Cloudflare R2 | Estado local, Spaces de DigitalOcean (mismo proveedor que el host) |
| 0008 | Observabilidad en Grafana Cloud con Alloy | Logs solo en el Droplet |
| 0009 | Solo GitHub Actions aplica y destruye | Aplicar desde la computadora del desarrollador |
| 0010 | Agentes de IA sin credenciales, en un dev container | Herramientas instaladas en la computadora local |

## Plantillas

Tres plantillas mantienen consistentes las apps, los PR y los procedimientos.

### `catalog/_template/app.yaml`

```yaml
# Copia esta carpeta a catalog/<nombre> y llena cada campo.
name: CAMBIAR              # kebab-case, igual que la carpeta
enabled: true              # false = apagar sin borrar
database:
  neon: false              # true = proyecto Neon + DATABASE_URL
services:
  web:
    image: ghcr.io/USUARIO/IMAGEN@sha256:DIGEST   # siempre por digest
    port: 3000
    public: true           # solo el frontend
    hostname: CAMBIAR.midominio.com
    healthcheck: /health
    memory_mb: 256
    env: {}
    secrets: []            # solo nombres; valores en secrets.enc.yaml
```

### `.github/pull_request_template.md`

```markdown
## Qué cambia
<!-- una o dos frases -->

## Apps afectadas
<!-- nombres de catalog/ o "plataforma" -->

## Checklist
- [ ] scripts/check.sh pasa
- [ ] Revisé el plan: solo cambia lo que dice este PR
- [ ] Sin destrucciones fuera de contenedores (o etiqueta allow-destroy y motivo)
- [ ] Secretos nuevos cifrados con sops
- [ ] ADR nuevo si hay una decisión de arquitectura
```

### `docs/runbooks/plantilla.md`

```markdown
# Título del problema

## Síntoma
Qué se ve (alerta, error, comportamiento).

## Causa probable

## Pasos
1. Verificar...
2. Corregir con un PR que...

## Qué no hacer

## Cómo confirmar que quedó resuelto
```

Runbooks a escribir en la fase 6: bloqueo del estado atascado, `apply` fallido a medias, el plan quiere reemplazar algo inesperado, una app no responde, el túnel cayó y rotación de un secreto filtrado.

### Fuentes

- [cc-sdd en GitHub](https://github.com/gotalab/cc-sdd)
- [Referencia de skills de cc-sdd](https://github.com/gotalab/cc-sdd/blob/main/docs/guides/skill-reference.md)
- [Claude Code en dev containers](https://code.claude.com/docs/en/devcontainer)
- [Configuración y permisos de Claude Code](https://docs.claude.com/en/docs/claude-code/settings)
- [Reglas por ruta en .claude/rules](https://developersdigest.tech/guides/claude-rules-directory)
- [Reglas de permisos y hooks que siempre se aplican](https://travis.media/blog/claude-code-permission-modes-explained/)
