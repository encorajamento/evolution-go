# Evolution GO — setup da Missão Encorajamento

Compose dedicado pro ambiente que alimenta o módulo WhatsApp do portal do encorajador.

## Diferenças vs. `docker/examples/docker-compose.yml`

- Porta host `4005:4000` (evita colisão com o backend Nest em 4000).
- `CONNECT_ON_STARTUP=true` — após restart do container, reconecta sozinho todas as instâncias que estavam online.
- `WEBHOOK_URL` global apontando pro backend (com shared-secret no path).
- `MINIO_ENABLED=true` + credenciais — faz upload das mídias recebidas pro S3/MinIO no momento em que chegam, evitando que URLs do WhatsApp expirem.
- `extra_hosts` com `host-gateway` — garante resolução de `host.containers.internal` em qualquer ambiente (Podman Linux inclusive).

## Uso

Jeito mais rápido (script detecta podman/docker, builda local e sobe):

```bash
./up.sh
```

Manual:

```bash
cp .env.example .env
# edita creds se necessário
podman compose up -d --build          # ou: docker compose up -d --build
```

A imagem é buildada do próprio repo (Dockerfile na raiz do evolution-go) e tagueada como `evolution-go:missao-local`.

Endpoints:

- API: `http://localhost:4005`
- Manager web: `http://localhost:4005/manager`

No backend Nest, `EVOLUTION_BASE_URL=http://localhost:4005`.

## Checklist de diagnóstico

1. `WHATSAPP_WEBHOOK_SECRET` no `.env` do backend = path do `EVOLUTION_WEBHOOK_URL`.
2. Backend Nest rodando (`lsof -iTCP:4000 -sTCP:LISTEN`).
3. Ao cadastrar instância no CRM, clicar em "Conectar" pra registrar subscriptions (`ALL`).
4. Manda msg de teste e confere `wpp_webhook_events` no banco do backend.
