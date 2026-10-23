# 0007. Estado cifrado en Cloudflare R2

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
El estado debe sobrevivir a la pérdida del Droplet o de la cuenta de DigitalOcean.

## Decisión
Backend S3 en el bucket R2 `tofu-state`, una llave por stack, cifrado por OpenTofu con pbkdf2 + aes_gcm.

## Alternativas consideradas
- Estado local: se pierde con la máquina.
- Spaces de DigitalOcean: mismo proveedor que el host.

## Consecuencias
El bucket se crea a mano una vez. Copia diaria con fecha y 30 días de retención. Sin la frase de cifrado no se puede leer el estado.
