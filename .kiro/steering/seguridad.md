# Checklist de seguridad

Fuente: docs/plan.md ("Checklist de seguridad"). La usa el subagente
security-auditor. Marca cada punto al implementarlo y revísalo completo
cada trimestre.

**Red y acceso**

- [ ] Cloud Firewall de DigitalOcean sin reglas de entrada
- [ ] SSH solo por Tailscale, solo con llaves, sin `root` y sin contraseñas
- [ ] ACL de Tailscale: solo tu usuario y `tag:ci` llegan al puerto 22 del servidor
- [ ] Un hostname explícito por servicio público en el túnel; todo lo demás responde 404
- [ ] Cloudflare en modo SSL Full (strict), HSTS activado y reglas de WAF y de límite de peticiones en los hostnames públicos

**Servidor y contenedores**

- [ ] `unattended-upgrades` con reinicio automático
- [ ] Docker sin socket expuesto por TCP; `daemon.json` endurecido
- [ ] Contenedores con `no-new-privileges`, límite de memoria y usuario no root en el Dockerfile
- [ ] Backends solo en la red de su app; ningún puerto publicado en el host
- [ ] Imágenes privadas en GHCR, fijadas por digest y escaneadas con Trivy en el CI de cada app

**Secretos y credenciales**

- [ ] Secretos solo en archivos SOPS; gitleaks y la verificación de cifrado en pre-commit y en CI
- [ ] Estado cifrado con `enforced = true`
- [ ] Tokens con el alcance mínimo y fecha de expiración, solo en los GitHub Environments `production` y `plan` (ADR 0011); en `plan`, de solo lectura donde el proveedor lo permita
- [ ] Frase del estado y llave age personal en tu gestor de contraseñas
- [ ] 2FA en GitHub, DigitalOcean, Cloudflare, Neon, Tailscale y Grafana

**Proceso**

- [ ] Rama `main` protegida; `apply` solo desde el CI
- [ ] Guardia contra destrucciones en el `plan`
- [ ] Detección diaria de cambios fuera de Git
- [ ] Simulacro de restauración en el último trimestre

## Cómo aplicarla en una revisión
- Cada hallazgo cita el punto de esta lista que incumple y `ruta:línea`.
- Severidad: crítica (expone tráfico, secretos o estado), alta (amplía
  permisos o rompe el aislamiento entre apps), media (falta fijar versión
  o digest), baja (documentación o higiene).
