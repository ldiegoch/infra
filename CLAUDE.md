# Proyecto infra

Infraestructura como código para un host de apps Docker: OpenTofu,
DigitalOcean, Cloudflare Tunnel, Neon, SOPS + age y GitHub Actions.

@.kiro/steering/constitucion.md

## Documentación (lee solo la sección que necesites)
- Plan y arquitectura: docs/plan.md
- Guía paso a paso y prompts de cada spec: docs/guia-implementacion.md
- Configuración de agentes: docs/configuracion-agentes.md
- Decisiones: docs/adr/ · Procedimientos: docs/runbooks/
- Ubica la sección con `grep -n '^##' <archivo>` y lee solo ese rango.

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
- Fusionar PRs, lanzar workflows, poner la etiqueta allow-destroy,
  usar --no-verify ni editar .claude/settings.json o .claude/hooks/:
  eso lo hace el humano.

## Cómo trabajar
- Cambios grandes: flujo de cc-sdd (abajo). Cambios del catálogo:
  subagente catalog-editor, sin spec.
- Antes de dar algo por terminado: scripts/check.sh debe pasar.
- Si una decisión no está en el plan ni en docs/adr/, propón un ADR con
  la plantilla en lugar de decidir por tu cuenta.
- Si algo requiere credenciales o tocar la nube, detente y explícame qué
  debo hacer yo.
- Piensa en inglés y responde en español. Todo Markdown de specs se
  escribe en el idioma de spec.json.language (es).

## Uso eficiente del contexto
- Respuestas breves: cita `ruta:línea` en lugar de pegar archivos.
- No releas archivos que no cambiaron; reutiliza el contexto.
- Delega revisiones y búsquedas amplias a subagentes (aíslan contexto).
- De la salida de comandos, muestra solo errores y el resumen.

## Flujo cc-sdd (skills en .claude/skills/kiro-*)
- Specs en `.kiro/specs/`; steering en `.kiro/steering/` (núcleo:
  product.md, tech.md, structure.md; seguridad.md cuando toque red,
  permisos, workflows o secretos).
- `/kiro-discovery` → `/kiro-spec-init` → `/kiro-spec-requirements` →
  `/kiro-spec-design` → `/kiro-spec-tasks` → `/kiro-impl` →
  `/kiro-validate-impl`. Progreso: `/kiro-spec-status <spec>`.
- Aprobación humana entre fases; no uses `-y` ni `--auto` salvo que
  te lo pidan. Solo se sigue con veredicto `GO` de /kiro-validate-impl.

## Comandos
- Verificación completa: ./scripts/check.sh
- Validar un stack: tofu -chdir=apps init -backend=false && tofu -chdir=apps validate
- Pruebas de módulos: tofu -chdir=modules/app test
- Probar el hook de seguridad: bash .claude/hooks/guard.test.sh
