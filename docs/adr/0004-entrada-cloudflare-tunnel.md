# 0004. Entrada solo por Cloudflare Tunnel, un hostname por app

- Estado: aceptado
- Fecha: 2026-10-23

## Contexto
El servidor no debe exponer puertos a Internet.

## Decisión
Todo el tráfico público entra por Cloudflare Tunnel con un hostname explícito por servicio público; cualquier otro nombre responde 404.

## Alternativas consideradas
- Puertos 80/443 abiertos: superficie de ataque directa.
- DNS comodín: expone hostnames no declarados.

## Consecuencias
Cloud Firewall sin reglas de entrada; administración solo por Tailscale. Cada servicio público necesita su registro DNS y su ruta en el túnel.
