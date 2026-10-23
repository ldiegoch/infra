# infra

Infraestructura como código para un host de apps Docker (OpenTofu,
DigitalOcean, Cloudflare Tunnel, Neon, SOPS + age y GitHub Actions),
desarrollada por agentes de IA con cc-sdd y aprobada por ti fase a fase.

- Plan: [docs/plan.md](docs/plan.md)
- Guía paso a paso: [docs/guia-implementacion.md](docs/guia-implementacion.md)
- Configuración de agentes: [docs/configuracion-agentes.md](docs/configuracion-agentes.md)

## Estado

Ya están hechos el Paso 2 (archivos del dev container) y los puntos 1 a 5
del Paso 3 de la guía:

- cc-sdd v3.1.0 instalado (`--claude-skills --lang es`): skills `/kiro-*`
  en `.claude/skills/` y plantillas en `.kiro/settings/`.
- Configuración de agentes: `CLAUDE.md`, `.claude/settings.json`,
  `.claude/hooks/`, subagentes, reglas por ruta, ADR 0000–0010 y plantillas.
- Steering: `.kiro/steering/` con product, tech, structure, constitucion y
  seguridad.

Lo que sigue: el punto 6 del Paso 3 (revisar y abrir el PR) y luego el
Paso 4 (`/kiro-discovery`).

## Primeros pasos

1. En GitHub, crea el repositorio privado `infra` **vacío** (sin README).
2. Desde esta carpeta:
   ```bash
   git remote add origin git@github.com:<usuario>/infra.git
   git push -u origin main
   git push -u origin chore/bootstrap-agentes
   ```
   Abre el PR de `chore/bootstrap-agentes` hacia `main`.
3. Protege `main` (PR obligatorio, checks en verde, sin force-push) y crea el
   Environment `production` limitado a `main`, con **Required reviewers =
   tú**, para que ningún `apply` corra sin tu clic.
4. En VS Code: "Dev Containers: Reopen in Container". En Windows, el
   contenedor va más rápido si, tras el push, usas "Dev Containers: Clone
   Repository in Container Volume".
5. En la terminal del contenedor: `claude` e inicia sesión. Comprueba el
   contrato de seguridad:
   - `bash .claude/hooks/guard.test.sh` debe dar todas las pruebas OK.
   - Pídele a Claude `ejecuta tofu apply`: debe quedar bloqueado.
6. En una **terminal aparte**: `age-keygen` dos veces (tú y el CI). Guarda
   ambas llaves privadas en tu gestor de contraseñas y borra los archivos.
7. Revisa `.kiro/steering/` y sigue con el Paso 4 de la guía.

Datos que el agente te pedirá en la spec `base-y-ci` y siguientes (solo los
públicos o los identificadores): las dos llaves **públicas** age, el
Account ID de Cloudflare, el Zone ID y el dominio, el correo de alertas y el
ID de tu llave SSH en DigitalOcean.

## Cómo está protegido el agente

| Capa | Qué hace |
| --- | --- |
| `CLAUDE.md`, `.claude/rules/`, `.kiro/steering/` | Instrucciones y la constitución, cargadas en cada sesión |
| `.claude/settings.json` | Permisos allow/ask/deny; el modo "bypass permissions" está desactivado |
| `.claude/hooks/guard.sh` | Revisa cada comando completo; falla cerrado si no puede leerlo |
| Dev container sin credenciales | Aunque se saltara lo anterior, no puede tocar la nube |
| PR + `plan` + Environment con aprobación | Nada llega a producción sin tu revisión |

Si inicias sesión con `gh auth login` dentro del contenedor, usa un token
fine-grained limitado al repositorio `infra` (Contents y Pull requests). El
hook bloquea `gh pr merge`, `gh workflow run`, `gh api`, `gh secret` y
poner la etiqueta `allow-destroy`.

## Ajustes respecto al texto del plan

Cambios de configuración (no de arquitectura) para seguridad, uso de
tokens y robustez:

- `CLAUDE.md` no importa `@docs/plan.md` completo en cada sesión (unos
  10 mil tokens); lo cita y pide leer solo la sección necesaria. Sí
  importa la constitución. Incluye el flujo de cc-sdd resumido.
- El plan está en tres archivos (`plan.md`, `guia-implementacion.md`,
  `configuracion-agentes.md`), así cada tarea lee solo lo que necesita.
- `guard.sh`: falla cerrado, detecta comandos entre comillas
  (`bash -c "tofu apply"`) y bloquea también `force-unlock`/`taint`, los
  comandos de `gh` que despliegan, `--no-verify`, force-push, push a
  `main` y la edición de su propia configuración. Trae 53 pruebas.
- `settings.json`: permite sin preguntar las verificaciones locales
  (menos interrupciones), niega leer estado, planes, `.terraform/` y
  llaves, y pide confirmación para editar la constitución.
- El hook de formato solo formatea el archivo `.tf` editado.
- `catalog-editor` usa el modelo `sonnet` (tarea acotada, más barata);
  los revisores heredan el modelo de la sesión.
- Dev container: versiones reales fijadas (OpenTofu 1.12.6, SOPS 3.13.3,
  age 1.3.2, Trivy 0.76.1, gitleaks 8.30.1, tflint 0.64.0), descargas
  verificadas con checksums y sin `curl | bash`; volumen de Claude con el
  dueño correcto; `pre-commit install` solo cuando existe su
  configuración; `safe.directory` para carpetas montadas desde Windows.
- `.gitattributes` fuerza LF para que los scripts no fallen por CRLF.
