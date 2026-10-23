# 0001. OpenTofu como herramienta de infraestructura como código

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
Toda la infraestructura y las apps se definen como código. El estado contiene secretos (variables de entorno de los contenedores) y debe cifrarse; el bloqueo del estado no debe requerir DynamoDB.

## Decisión
Usar OpenTofu 1.10 o superior, con cifrado de estado nativo y bloqueo `use_lockfile` en el backend S3.

## Alternativas consideradas
- Terraform: sin cifrado de estado nativo.

## Consecuencias
Mismos providers que Terraform. Cifrado obligatorio (`enforced = true`) de estado y plan. Pendiente de verificar que R2 acepte las escrituras condicionales de `use_lockfile`; si no, el grupo de concurrencia del CI basta.
