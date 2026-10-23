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
