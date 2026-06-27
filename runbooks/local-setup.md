# Local Setup Runbook

## Prerequisites

- Docker Engine 24+ and Docker Compose v2
- 8+ GB free RAM (social profile needs 3-4 GB)
- 20+ GB free disk
- Python 3.12+ (for MarkItDown API tests, optional)

## First-Time Setup

### 1. Clone and configure

```bash
cd /Users/defiankit/Desktop/lyrafin-ops-infra
cp .env.example .env
# Edit .env with your local dev values — no real secrets needed locally
```

### 2. Start the email profile (listmonk + Mailpit)

```bash
docker compose --profile email up -d
```

Verify:
- listmonk: http://localhost:9001
- Mailpit: http://localhost:8025

First listmonk login: use `LISTMONK_ADMIN_USER` and `LISTMONK_ADMIN_PASSWORD` from `.env`.

### 3. Start the social profile (Postiz + Temporal stack)

```bash
docker compose --profile social up -d
```

This starts:
- Postiz (port 5050)
- Postiz Postgres + Redis
- Temporal + Temporal Postgres + Elasticsearch + Temporal UI (port 8080)

Wait ~2 minutes for all services to become healthy (Temporal + Elasticsearch have long start periods).

Verify:
- Postiz: http://localhost:5050
- Temporal UI: http://localhost:8080

```bash
docker compose --profile social ps
```

All containers should show `healthy` status.

### 4. Start the convert profile (MarkItDown API)

```bash
docker compose --profile convert up -d --build
```

Verify:
- Health: http://localhost:9100/health

### 5. Start everything at once

```bash
docker compose --profile all up -d
```

### 6. Run smoke tests

```bash
./scripts/smoke-local.sh
```

### 7. Test MarkItDown API

```bash
# Health check
curl http://localhost:9100/health

# Convert a text file
curl -X POST http://localhost:9100/v1/convert/file \
  -H "X-API-Key: local-dev-token" \
  -F "file=@/path/to/test.docx"

# Test auth rejection
curl -X POST http://localhost:9100/v1/convert/file \
  -F "file=@test.txt"
# Should return 401
```

## Stopping Services

```bash
# Stop a specific profile
docker compose --profile email down

# Stop everything
docker compose --profile all down

# Stop and remove volumes (WARNING: destroys data)
docker compose --profile all down -v
```

## Viewing Logs

```bash
docker compose logs -f listmonk
docker compose logs -f postiz
docker compose logs -f temporal
docker compose logs -f markitdown-api
```

## Backup and Restore (Local)

```bash
# Backup all databases
./scripts/backup-postgres.sh

# Restore a specific database
./scripts/restore-postgres.sh listmonk ./backups/listmonk_<timestamp>.sql.gz
```

## Pointing multiasset-ai to Local Services

Set these in `multiasset-ai`'s `.env`:

```env
LISTMONK_BASE_URL=http://localhost:9001
LISTMONK_API_USER=local
LISTMONK_API_TOKEN=local-dev-token
LISTMONK_BLOG_LIST_ID=1
LISTMONK_TRANSACTIONAL_TEMPLATE_ID=1

POSTIZ_BASE_URL=http://localhost:5050
POSTIZ_API_TOKEN=local-dev-token

MARKITDOWN_BASE_URL=http://localhost:9100
MARKITDOWN_API_KEY=local-dev-token
```
