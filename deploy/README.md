# Deploy — Evolution GO (fork Missão Encorajamento)

Documentação do deploy do fork da Evolution GO no Docker Swarm da Missão
Encorajamento.

## Visão geral

- **Pipeline**: Jenkins → build → push GHCR (`ghcr.io/encorajamento/evolution-go`)
  → SSH `deploy@192.168.10.120` → `docker stack deploy`.
- **Branch de deploy**: `missao` no fork. A `main` do fork espelha upstream
  e não gera deploy.
- **Postgres**: externo em `192.168.10.100:5432` (não bundled na stack).
- **Storage de mídia**: MinIO em `s3.encorajamento.com.br`.

## Pré-requisitos (setup único)

### 1. Postgres no `192.168.10.100`

Conectado como superuser:

```bash
psql -h 192.168.10.100 -U postgres
```

```sql
CREATE USER evolution WITH PASSWORD 'evogo_5J9qK2pX7sH8nM3rL6tF';
CREATE DATABASE evogo_auth OWNER evolution;
CREATE DATABASE evogo_users OWNER evolution;
GRANT ALL PRIVILEGES ON DATABASE evogo_auth TO evolution;
GRANT ALL PRIVILEGES ON DATABASE evogo_users TO evolution;

\c evogo_auth
GRANT ALL ON SCHEMA public TO evolution;

\c evogo_users
GRANT ALL ON SCHEMA public TO evolution;
```

Teste:

```bash
psql -h 192.168.10.100 -U evolution -d evogo_auth -c "SELECT current_user;"
```

### 2. Volume `evolution_data` no nó manager do Swarm

O volume guarda dados auxiliares do `/app/dbdata` (algumas configs e cache que
o evolution-go cria fora do Postgres). É declarado `external: true` na stack
pra sobreviver a `stack rm`.

Via Portainer UI:
1. Menu → **Volumes** → **Add volume**
2. Name: `evolution_data`
3. Driver: `local`
4. Create

Ou via CLI no nó manager:

```bash
docker volume create evolution_data
```

### 3. Rede `public`

Compartilhada com Traefik. Já deve existir (todas as stacks da Missão usam).
Confirmar:

```bash
docker network ls | grep public
```

### 4. Credenciais no Jenkins

Reusa credenciais do GE:
- `ghcr-token` — secret text (Personal Access Token do GitHub com `write:packages`).
- `swarm-deploy-key` — SSH private key (chave do user `deploy` no `192.168.10.120`).

### 5. GHCR — imagem precisa ser acessível pelo Swarm

Após o primeiro push, garantir que a imagem `ghcr.io/encorajamento/evolution-go`
está visível pro user que faz `docker login` no swarm. Se for privada,
configurar acesso via `--with-registry-auth` no deploy (já está no Jenkinsfile).

## Variáveis de ambiente

| Variável | Onde está | Observação |
|---|---|---|
| `GLOBAL_API_KEY` | `swarm.prod.yml` | API key global da Evolution. Rotacionar via Portainer se vazar. |
| `POSTGRES_AUTH_DB` | `swarm.prod.yml` | Connection string DB whatsmeow (sessões). |
| `POSTGRES_USERS_DB` | `swarm.prod.yml` | Connection string DB de instâncias/labels. |
| `WEBHOOK_URL` | **PLACEHOLDER** | Editar via Portainer após deploy. Aponta pro `/api/public/whatsapp/webhook/<secret>` do backend GE. |
| `MINIO_*` | `swarm.prod.yml` | Bucket S3 pra mídia. |
| `CONNECT_ON_STARTUP` | `swarm.prod.yml` | `true` — reconecta instâncias salvas no boot. |

> **Nota**: hoje as credenciais estão em texto claro no YAML porque o repo é
> privado e a rede é interna. Se precisar reforçar, mover `MINIO_SECRET_KEY`
> e `GLOBAL_API_KEY` pra Docker Secrets.

## URL pública

- `https://ev.encorajamento.com.br` — Traefik roteia pra porta 4000 do container.
- `https://ev.encorajamento.com.br/health` — healthcheck.

## Migração inicial (one-shot)

Se ainda há dados em outro Postgres local (ex.: ambiente Podman do dev),
exportar com `pg_dump -Fc` e restaurar:

```bash
pg_restore -h 192.168.10.100 -U evolution -d evogo_auth \
  --clean --if-exists --no-owner --role=evolution evogo_auth.dump

pg_restore -h 192.168.10.100 -U evolution -d evogo_users \
  --clean --if-exists --no-owner --role=evolution evogo_users.dump
```

Após o restore, atualizar o webhook das instâncias pra apontar pro endpoint
público (em vez do `host.containers.internal:4000` que vem do dev):

```sql
UPDATE instances
   SET webhook = 'https://grupos.encorajamento.com.br/api/public/whatsapp/webhook/<SECRET>';
```

## Deploy

### Automático (Jenkins)

Push em `missao` → build → push GHCR → deploy.

### Manual (debug/rollback)

```bash
# Servidor swarm
ssh deploy@192.168.10.120

# Confirmar stack
docker stack ls
docker stack ps evolution-go

# Forçar redeploy com a mesma imagem
docker service update --force evolution-go_evolution-go
```

## Status, logs, troubleshooting

```bash
ssh deploy@192.168.10.120 docker service ls | grep evolution
ssh deploy@192.168.10.120 docker service logs -f evolution-go_evolution-go
ssh deploy@192.168.10.120 docker service ps evolution-go_evolution-go --no-trunc
```

### Container reiniciando

1. Confirmar Postgres acessível do nó swarm:
   ```bash
   ssh deploy@192.168.10.120 'pg_isready -h 192.168.10.100 -p 5432'
   ```
2. Confirmar credenciais do Postgres OK:
   ```bash
   ssh deploy@192.168.10.120 'psql -h 192.168.10.100 -U evolution -d evogo_auth -c "SELECT 1;"'
   ```
3. Healthcheck — `curl http://localhost:4000/health` dentro do container:
   ```bash
   docker exec $(docker ps -qf name=evolution-go_evolution-go) wget -qO- http://localhost:4000/health
   ```

### Webhook não chegando no backend GE

1. Confirmar `WEBHOOK_URL` no Portainer.
2. Conferir que o secret bate com o do backend.
3. Logs do evolution-go geralmente mostram `webhook delivery failed: ...`.

### Sessão WhatsApp desconectada após deploy

O `update_config: order: stop-first` minimiza isso, mas se aconteceu,
confirma que nenhuma outra instância (dev local ou outro server) está
rodando a mesma sessão. Se houver, o WhatsApp desconecta uma das duas.
Solução: identificar e parar a outra; nas instâncias afetadas, gerar QR
novo via `/instance/connect/{instanceName}`.

## Rollback

Docker Swarm faz **rollback automático** se o healthcheck falhar nos primeiros
90s (`monitor: 90s`, `failure_action: rollback`).

Rollback manual pra commit anterior:

```bash
ssh deploy@192.168.10.120
sed -i 's|:CURRENT_TAG|:PREVIOUS_TAG|g' /opt/stacks/evolution-go.yml
docker stack deploy \
  --with-registry-auth \
  --resolve-image always \
  -c /opt/stacks/evolution-go.yml \
  evolution-go
```

Identificar tag anterior:

```bash
docker service ps evolution-go_evolution-go --no-trunc | head -5
```

## Estrutura

```
evolution-go/
├── Jenkinsfile            # Pipeline (checkout → build → push → deploy)
└── deploy/
    ├── swarm.prod.yml     # Stack definition
    └── README.md          # Este arquivo
```
