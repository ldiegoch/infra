# 0006. Secretos con SOPS + age en el repositorio

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Los secretos deben versionarse junto a la configuración sin estar nunca en texto plano.

## Decisión
Archivos `secrets.enc.yaml` cifrados con SOPS + age, con dos destinatarios: la llave personal y la del CI. OpenTofu los lee con `carlpett/sops`.

## Alternativas consideradas
- Variables solo en el CI: fuera de Git, sin historial.
- Gestor de secretos externo: otro servicio y otra credencial.

## Consecuencias
Los nombres de las variables quedan visibles en los PR. Pre-commit y CI rechazan archivos sin metadatos de SOPS. Perder la llave age personal impide leer los secretos.
