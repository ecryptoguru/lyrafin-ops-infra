# Lyrafin Ops Infrastructure — Codebase Reference

> Complete technical documentation of the `lyrafin-ops-infra` repository.
> Generated 2026-06-22. Updated 2026-06-27 after production preflight hardening, source-of-truth doc cleanup, and local Docker validation.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Docker Compose](#4-docker-compose)
5. [Email Profile — listmonk](#5-email-profile--listmonk)
6. [Social Profile — Postiz + Temporal](#6-social-profile--postiz--temporal)
7. [Convert Profile — MarkItDown API](#7-convert-profile--markitdown-api)
8. [Caddy Reverse Proxy](#8-caddy-reverse-proxy)
9. [Scripts](#9-scripts)
10. [Runbooks](#10-runbooks)
11. [Environment Variables](#11-environment-variables)
12. [Security](#12-security)
13. [Testing](#13-testing)
14. [Production Deployment](#14-production-deployment)
15. [Known Decisions & Trade-offs](#15-known-decisions--trade-offs)

---

## 1. Project Overview

**Purpose:** Deploy and operate three open-source services for Lyrafin AI:

| Service | Role | Source |
|---|---|---|
| [listmonk](https://github.com/knadh/listmonk) | Newsletter + transactional email | `listmonk/listmonk:latest` |
| [Postiz](https://github.com/gitroomhq/postiz-app) | Social media scheduling | `ghcr.io/gitroomhq/postiz-app:latest` |
| [MarkItDown](https://github.com/microsoft/markitdown) | Document-to-markdown conversion | Custom FastAPI wrapper, `python:3.13-slim-bullseye` |

**Production target:** Contabo Cloud VPS 10 (4 vCPU, 8 GB RAM, 150 GB SSD, Ubuntu 24.04 LTS).

**Production domains:**

- `newsletter.lyrafinai.com` → listmonk
- `social.lyrafinai.com` → Postiz
- `convert.lyrafinai.com` → MarkItDown API

**Secrets management:** [Doppler CLI](https://doppler.com) — never commit real secrets to git.

---

## 2. Architecture

```
                    Internet
                       |
                  [Contabo VPS]
                       |
              [UFW: 22, 80, 443]
                       |
                   [Caddy :80/:443]
                   /     |     \
                  /      |      \
   newsletter.   social.   convert.
   lyrafinai.com lyrafinai.com lyrafinai.com
         |            |            |
   [listmonk:9000] [postiz:5000] [markitdown-api:9100]
         |            |            |
   [listmonk-db]  [postiz-pg]     (no DB)
         |        [postiz-redis]
         |        [temporal:7233]
         |        [temporal-pg]
         |        [temporal-es]
         |        [temporal-ui:8080]
         |
   [Mailpit:8025] (local dev only)
```

**Networks:**

| Network | Services | Purpose |
|---|---|---|
| `lyra-net` | listmonk, listmonk-db, mailpit, markitdown-api, caddy | Email + convert services |
| `postiz-network` | postiz, postiz-postgres, postiz-redis, caddy | Postiz app services |
| `temporal-network` | temporal, temporal-postgresql, temporal-elasticsearch, temporal-ui, postiz | Temporal workflow stack (shared with Postiz) |

**Volumes (Docker named volumes):**

| Volume | Service | Data |
|---|---|---|
| `listmonk-db-data` | listmonk-db | PostgreSQL data |
| `listmonk-uploads` | listmonk | Uploaded images/files |
| `postiz-db-data` | postiz-postgres | PostgreSQL data |
| `postiz-redis-data` | postiz-redis | Redis persistence |
| `postiz-config` | postiz | App configuration |
| `postiz-uploads` | postiz | Media uploads |
| `temporal-postgres-data` | temporal-postgresql | Temporal PostgreSQL data |
| `temporal-elasticsearch-data` | temporal-elasticsearch | ES index data |
| `caddy-data` | caddy | TLS certificates + logs |
| `caddy-config` | caddy | Caddy autosave config |

---

## 3. Repository Structure

```txt
lyrafin-ops-infra/
├── docker-compose.yml              # Main compose — all services, profiles, networks, volumes
├── docker-compose.override.yml     # Local dev overrides (auto-merged by Docker Compose)
├── docker-compose.prod.yml         # Production overrides (used with -f flag, bypasses override)
├── .env.example                    # Environment variable template (copy to .env)
├── .gitignore                      # Ignores .env, backups, volumes, .DS_Store, etc.
├── README.md                       # Project README with quick start
├── lyra-ops-final.md               # Original planning document
├── codebase.md                     # This file
├── a.scpt                          # Local AppleScript helper artifact
│
├── .devin/                         # AG Kit agent/workflow helper bundle
│   ├── ARCHITECTURE.md             # AG Kit overview
│   ├── agents/                     # Specialist agent persona docs
│   ├── rules/                      # Local agent rules
│   ├── scripts/                    # Validation/session helper scripts
│   └── workflows/                  # Slash-command workflow docs
│
├── caddy/
│   └── Caddyfile                   # Reverse proxy config: TLS, security headers, logging
│
├── listmonk/
│   ├── config.toml                 # Reference config (Docker uses env vars instead)
│   └── README.md                   # listmonk setup notes, SES config, list design
│
├── postiz/
│   ├── README.md                   # Postiz config notes, OAuth setup, MCP server docs
│   └── dynamicconfig/
│       └── development-sql.yaml    # Temporal dynamic config (mounted into temporal container)
│
├── markitdown-api/
│   ├── Dockerfile                  # Python 3.13-slim, ffmpeg, exiftool, non-root user
│   ├── .dockerignore               # Excludes .env, .git, __pycache__, venvs
│   ├── requirements.txt            # markitdown[all], fastapi, uvicorn, pydantic, pytest
│   ├── app/
│   │   ├── __init__.py             # Empty package marker
│   │   ├── main.py                 # FastAPI app: endpoints, auth wiring
│   │   ├── convert.py              # Core conversion logic: validation, tempfile, timeout
│   │   ├── config.py               # Pydantic Settings + allowed MIME types/extensions
│   │   └── security.py             # API key verification via HMAC compare_digest
│   └── tests/
│       ├── __init__.py             # Empty package marker
│       ├── pytest.ini              # testpaths = tests
│       └── test_api.py             # 10 tests: health, auth, validation, conversion, security
│
├── scripts/
│   ├── smoke-local.sh              # Local smoke tests (curl health endpoints)
│   ├── preflight-prod.sh           # Production safety gate for secrets, ports, SMTP, registration
│   ├── backup-postgres.sh          # Backup all 3 PostgreSQL databases to ./backups/
│   ├── restore-postgres.sh         # Restore a specific database from backup
│   └── doctor.sh                   # Daily health check: disk, containers, logs, endpoints
│
└── runbooks/
    ├── local-setup.md              # Local development setup guide
    ├── contabo-bootstrap.md        # VPS provisioning + hardening + Docker + Doppler
    ├── deploy.md                   # Production deployment steps
    ├── backup-restore.md           # Backup strategy, manual/automated backups, restore drills
    └── incident-response.md        # Severity levels, triage, common incidents
```

---

## 4. Docker Compose

### 4.1 `docker-compose.yml` — Main File

**Profiles:**

| Profile | Services | Use Case |
|---|---|---|
| `email` | listmonk, listmonk-db, mailpit | Email testing |
| `social` | postiz, postiz-postgres, postiz-redis, temporal, temporal-postgresql, temporal-elasticsearch, temporal-ui | Social media scheduling |
| `convert` | markitdown-api | Document conversion |
| `all` | All of the above | Full local dev |
| `production` | caddy | Reverse proxy (combined with `all` for production) |

**YAML anchors:**

```yaml
x-email-common: &email-common
  profiles: [email, all]

x-social-common: &social-common
  profiles: [social, all]

x-convert-common: &convert-common
  profiles: [convert, all]
```

**Service startup commands:**

- **listmonk**: `sh -c "./listmonk --install --idempotent --yes --config '' && ./listmonk --upgrade --yes --config '' && ./listmonk --config ''"` — auto-installs schema on first boot, upgrades on subsequent boots, then starts the server.
- **Postiz**: Default entrypoint from the official image.
- **Temporal**: Uses `temporalio/auto-setup:1.28.1` which auto-creates namespaces and schema.
- **MarkItDown API**: `uvicorn app.main:app --host 0.0.0.0 --port 9100`

**Healthchecks:**

| Service | Method | Interval | Start Period |
|---|---|---|---|
| listmonk | `wget --spider http://localhost:9000/` | 30s | 30s |
| listmonk-db | `pg_isready -U listmonk` | 10s | — |
| postiz | Node.js HTTP GET to `localhost:5000/` (status < 500) | 30s | 120s |
| postiz-postgres | `pg_isready` | 10s | 10s |
| postiz-redis | `redis-cli ping` | 10s | 5s |
| temporal | `temporal operator cluster health` | 10s | 30s |
| temporal-elasticsearch | `curl _cluster/health?wait_for_status=yellow` | 10s | 60s |
| temporal-postgresql | `pg_isready` | 10s | 10s |
| temporal-ui | `curl http://localhost:8080/healthz` | 30s | 20s |
| markitdown-api | `curl -f http://localhost:9100/health` | 30s | 15s |

**Depends_on (with conditions):**

- listmonk → listmonk-db (service_healthy)
- postiz → postiz-postgres (service_healthy), postiz-redis (service_healthy), temporal (service_healthy)
- temporal → temporal-postgresql (service_healthy), temporal-elasticsearch (service_healthy)
- temporal-ui → temporal (service_healthy)
- caddy → **none** (cross-profile deps removed; start Caddy after other services are up)

### 4.2 `docker-compose.override.yml` — Local Dev

Auto-merged by Docker Compose when running without explicit `-f` flags.

**Overrides:**

- listmonk SMTP → Mailpit (`mailpit:1025`, no auth, no TLS)
- listmonk depends_on → adds `mailpit: service_started`

### 4.3 `docker-compose.prod.yml` — Production

Used with explicit `-f` flags to **bypass** the auto-merged override file:

```bash
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production up -d
```

**Overrides:**

| Service | Change | Reason |
|---|---|---|
| listmonk | SMTP → SES (`SES_SMTP_HOST`, port 587, STARTTLS, login auth) | Production email delivery |
| listmonk | Requires admin + DB secrets | Prevents inherited local placeholders |
| listmonk | `ports: !reset []` | Not publicly accessible; Caddy proxies |
| listmonk-db | `ports: !reset []` | Not publicly accessible |
| listmonk-db | Requires DB password | Prevents inherited local placeholders |
| mailpit | `ports: !reset []` | Not needed in production |
| postiz | `ports: !reset []` | Not publicly accessible; Caddy proxies |
| postiz | URLs → `https://social.lyrafinai.com` | Production domain |
| postiz | Requires JWT + DB secrets; `DISABLE_REGISTRATION: true` | Prevents inherited placeholders and open signup |
| postiz-postgres | Requires DB password | Prevents inherited local placeholders |
| markitdown-api | `ports: !reset []` | Not publicly accessible; Caddy proxies |
| markitdown-api | Requires API key | Prevents inherited `local-dev-token` |
| temporal | `ports: !reset []` | Not publicly accessible |
| temporal / temporal-postgresql | Requires DB password | Prevents inherited local placeholders |
| temporal-ui | `ports: !reset []` | Not publicly accessible |

**Result in production:** Only ports 80 and 443 (Caddy) are exposed publicly.

---

## 5. Email Profile — listmonk

### 5.1 Service Configuration

- **Image:** `listmonk/listmonk:latest`
- **Container:** `listmonk_app`
- **Internal port:** 9000 (mapped to `${LISTMONK_PORT:-9001}` locally, reset in prod)
- **Database:** `postgres:17-alpine` (`listmonk-db`, port 5432 bound to 127.0.0.1)
- **SMTP (local):** Mailpit (`axllent/mailpit:latest`, internal SMTP on 1025, web UI published on 8025)
- **SMTP (production):** Amazon SES via `docker-compose.prod.yml`

### 5.2 Environment Variables

listmonk uses the `LISTMONK_` prefix for all config. Nested keys use double underscores:

| Env Var | Config Path | Default |
|---|---|---|
| `LISTMONK_app__address` | app.address | `0.0.0.0:9000` |
| `LISTMONK_db__user` | db.user | `listmonk` |
| `LISTMONK_db__password` | db.password | `listmonk` |
| `LISTMONK_db__database` | db.database | `listmonk` |
| `LISTMONK_db__host` | db.host | `listmonk-db` |
| `LISTMONK_db__port` | db.port | `5432` |
| `LISTMONK_db__ssl_mode` | db.ssl_mode | `disable` |
| `LISTMONK_smtp__host` | smtp.host | (empty; overridden by override/prod) |
| `LISTMONK_smtp__port` | smtp.port | (empty; overridden by override/prod) |
| `LISTMONK_smtp__auth_protocol` | smtp.auth_protocol | (empty; overridden) |
| `LISTMONK_smtp__username` | smtp.username | (empty; overridden) |
| `LISTMONK_smtp__password` | smtp.password | (empty; overridden) |
| `LISTMONK_smtp__tls_type` | smtp.tls_type | (empty; overridden) |
| `LISTMONK_smtp__hello_host` | smtp.hello_host | (empty; overridden) |
| `LISTMONK_ADMIN_USER` | — (used by `--install` command) | (empty) |
| `LISTMONK_ADMIN_PASSWORD` | — (used by `--install` command) | (empty) |

### 5.3 Reference Files

- `listmonk/config.toml` — Reference for non-Docker deployments. Documents both Mailpit (local) and SES (production) SMTP settings.
- `listmonk/README.md` — Notes on SES configuration, initial list design (`blog_subscribers`, `product_updates`, `trial_onboarding`, `reengagement`, `creator_referrals`, `internal_test`), and SES bounce webhook URL.

### 5.4 Mailpit (Local Dev Only)

- **Image:** `axllent/mailpit:latest`
- **Container:** `listmonk_mailpit`
- **Port:** `${MAILPIT_SMTP_PORT:-8025}:8025` publishes the web UI locally; listmonk uses internal SMTP `mailpit:1025`
- **Env:** `MP_SMTP_AUTH_ACCEPT_ANY=1`, `MP_SMTP_AUTH_ALLOW_INSECURE=1`
- **Production:** Ports reset to empty (not accessible)

---

## 6. Social Profile — Postiz + Temporal

### 6.1 Postiz

- **Image:** `ghcr.io/gitroomhq/postiz-app:latest`
- **Container:** `postiz`
- **Internal port:** 5000 (mapped to `${POSTIZ_PORT:-5050}` locally, reset in prod)
- **Restart:** `always` (not `unless-stopped` — Postiz should always restart in production)
- **Volumes:** `postiz-config:/config/`, `postiz-uploads:/uploads/`

**Key environment variables:**

| Variable | Value | Notes |
|---|---|---|
| `IS_GENERAL` | `true` | Required for self-hosted routing |
| `DISALLOW_PLUS` | `true` | Hides cloud billing UI |
| `DISABLE_REGISTRATION` | `false` (local) / `true` (prod override) | Local setup stays open; production is forced closed unless the deploy path is intentionally changed |
| `STORAGE_PROVIDER` | `local` | Local Docker volume for v1 |
| `UPLOAD_DIRECTORY` | `/uploads` | Mapped to `postiz-uploads` volume |
| `RUN_CRON` | `true` | Enables Postiz cron scheduler |
| `API_LIMIT` | `30` | API rate limit |
| `TEMPORAL_ADDRESS` | `temporal:7233` | Temporal workflow engine |
| `DATABASE_URL` | `postgresql://...@postiz-postgres:5432/...` | Postgres connection |
| `REDIS_URL` | `redis://postiz-redis:6379` | Redis connection |
| `BACKEND_INTERNAL_URL` | `http://localhost:3000` | Internal backend URL |
| `JWT_SECRET` | (from env) | JWT signing secret |
| `OPENAI_API_KEY` | (from env, optional) | For AI features |

**Social provider OAuth credentials (injected via Doppler in production):**

- `LINKEDIN_CLIENT_ID` / `LINKEDIN_CLIENT_SECRET`
- `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET`
- `YOUTUBE_CLIENT_ID` / `YOUTUBE_CLIENT_SECRET`
- **X/Twitter intentionally not configured** — handled via Hyperagent native connector

**Healthcheck:** Node.js inline script that does `http.get('http://localhost:5000/')` and exits 0 if status < 500, 1 otherwise. Timeout: 4 seconds.

**Postiz MCP Server:**

```
URL: https://social.lyrafinai.com/mcp
Header: Authorization: Bearer {POSTIZ_API_KEY}
Transport: Streamable HTTP
```

Get API key from: Postiz Settings → Developers → Public API.

### 6.2 Postiz PostgreSQL

- **Image:** `postgres:17-alpine`
- **Container:** `postiz-postgres`
- **No public port** (only on `postiz-network`)
- **Healthcheck:** `pg_isready -U postiz-user -d postiz-db-local`

### 6.3 Postiz Redis

- **Image:** `redis:7.2`
- **Container:** `postiz-redis`
- **No public port** (only on `postiz-network`)
- **Healthcheck:** `redis-cli ping | grep -q PONG`

### 6.4 Temporal Stack

#### temporal-elasticsearch

- **Image:** `elasticsearch:7.17.27`
- **Container:** `temporal-elasticsearch`
- **Network:** `temporal-network` only (exposed via `expose: 9200`, not published)
- **Config:** Single-node, security disabled, 256m heap
- **Disk watermarks:** low=512mb, high=256mb, flood=128mb
- **Healthcheck:** `curl _cluster/health?wait_for_status=yellow&timeout=5s`
- **Start period:** 60s (ES is slow to start)

#### temporal-postgresql

- **Image:** `postgres:16`
- **Container:** `temporal-postgresql`
- **Network:** `temporal-network` only
- **Healthcheck:** `pg_isready -U temporal`

#### temporal

- **Image:** `temporalio/auto-setup:1.28.1`
- **Container:** `temporal`
- **Port:** `127.0.0.1:7233:7233` (localhost only, reset in prod)
- **Config:** `DB=postgres12`, `ENABLE_ES=true`, `ES_VERSION=v7`, `TEMPORAL_NAMESPACE=default`
- **Dynamic config:** Mounted from `./postiz/dynamicconfig/development-sql.yaml`
- **Healthcheck:** `temporal operator cluster health --address temporal:7233`
- **Depends on:** temporal-postgresql (healthy), temporal-elasticsearch (healthy)

#### temporal-ui

- **Image:** `temporalio/ui:2.34.0`
- **Container:** `temporal-ui`
- **Port:** `127.0.0.1:8080:8080` (localhost only, reset in prod)
- **Config:** `TEMPORAL_ADDRESS=temporal:7233`, `TEMPORAL_CORS_ORIGINS=http://127.0.0.1:3000`
- **Healthcheck:** `curl -f http://localhost:8080/healthz`
- **Depends on:** temporal (healthy)

#### Temporal Dynamic Config

`postiz/dynamicconfig/development-sql.yaml`:

```yaml
system.forceSearchAttributesCacheRefreshOnRead:
  - value: true
```

Mounted into the temporal container at `/etc/temporal/config/dynamicconfig/development-sql.yaml`.

---

## 7. Convert Profile — MarkItDown API

### 7.1 Overview

A custom FastAPI application that wraps Microsoft's MarkItDown library to provide a REST API for converting documents to markdown. Runs as a non-root user (UID 1001) inside a Docker container.

### 7.2 Dockerfile

```dockerfile
FROM python:3.13-slim-bullseye
ENV DEBIAN_FRONTEND=noninteractive
ENV EXIFTOOL_PATH=/usr/bin/exiftool
ENV FFMPEG_PATH=/usr/bin/ffmpeg

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg exiftool curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip --no-cache-dir install -r requirements.txt
COPY app/ ./app/
COPY tests/ ./tests/

RUN useradd -r -u 1001 -g root appuser && chown -R appuser:root /app
USER 1001

EXPOSE 9100
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9100"]
```

**System dependencies:** `ffmpeg` (audio/video transcription), `exiftool` (image EXIF metadata), `curl` (healthcheck).

### 7.3 Requirements

```txt
markitdown[all]>=0.0.1
fastapi>=0.115.0
uvicorn[standard]>=0.34.0
python-multipart>=0.0.18
pydantic>=2.0.0
pydantic-settings>=2.0.0
pytest>=8.0.0
httpx>=0.27.0
```

### 7.4 Application Code

#### `app/config.py` — Settings & Validation

Uses Pydantic `BaseSettings` with `env_prefix="MARKITDOWN_"`:

| Setting | Env Var | Default | Type |
|---|---|---|---|
| `api_key` | `MARKITDOWN_API_KEY` | `local-dev-token` | str |
| `azure_document_intelligence_endpoint` | `MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | `""` | str |
| `azure_document_intelligence_key` | `MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_KEY` | `""` | str |
| `max_file_size_mb` | `MARKITDOWN_MAX_FILE_SIZE_MB` | `50` | int |
| `conversion_timeout_seconds` | `MARKITDOWN_CONVERSION_TIMEOUT_SECONDS` | `120` | int |

**Allowed MIME types:** PDF, Office formats (docx, pptx, xlsx, doc, ppt, xls), CSV, HTML, plain text, markdown, JSON, images (PNG, JPEG, GIF, WebP, BMP, TIFF), audio (MP3, WAV), video (MP4), ZIP.

**Allowed extensions:** `.pdf`, `.docx`, `.pptx`, `.xlsx`, `.xls`, `.doc`, `.ppt`, `.csv`, `.html`, `.htm`, `.txt`, `.md`, `.json`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`, `.tiff`, `.tif`, `.mp3`, `.wav`, `.mp4`, `.zip`.

**Generic MIME fallback:** `application/octet-stream` and `binary/octet-stream` are accepted when the file extension is valid (common with `curl` uploads).

#### `app/security.py` — API Key Verification

```python
def verify_api_key(x_api_key: str | None = Header(None, alias="X-API-Key")) -> None:
```

- Uses `hmac.compare_digest()` for constant-time comparison (prevents timing attacks)
- Returns 401 for missing or invalid API keys
- Also returns 401 if `settings.api_key` is not configured (fail-closed)

#### `app/convert.py` — Core Conversion Logic

**Flow:**

1. Read file content from `UploadFile`
2. Sanitize filename via `os.path.basename()` (prevents path traversal)
3. Validate: file size, extension (must have one), MIME type (with generic fallback)
4. Create temp directory via `tempfile.mkdtemp(prefix="markitdown_")`
5. Write file to temp dir
6. Convert via `asyncio.to_thread(mkd.convert, file_path)` with `asyncio.wait_for` timeout
7. Return JSON response with filename, content_type, size, text, duration_ms
8. Cleanup: `shutil.rmtree(tmp_dir, ignore_errors=True)` in `finally` block

**Error handling:**

| Condition | HTTP Status |
|---|---|
| File size > max | 413 |
| No file extension | 415 |
| Unsupported extension | 415 |
| Unsupported MIME type (non-generic) | 415 |
| Conversion timeout | 504 |
| Conversion failure | 422 |
| Missing/invalid API key | 401 |

**MarkItDown singleton:** `_mkd` is lazily initialized. If `azure_document_intelligence_endpoint` is set, it's passed as `docintel_endpoint` to the `MarkItDown` constructor.

#### `app/main.py` — FastAPI Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | No | Health check (returns `{"status": "ok", "azure_doc_intel": bool}`) |
| POST | `/v1/convert/file` | `X-API-Key` header | Convert uploaded file to markdown |
| POST | `/v1/convert/blob` | `X-API-Key` header | Alias for `/v1/convert/file` |

**Note:** `POST /v1/convert/url` is intentionally not implemented (SSRF risk — add later with URL allowlisting).

**Response format (200):**

```json
{
  "filename": "test.txt",
  "content_type": "text/plain",
  "size_bytes": 14,
  "text": "Hello, Lyrafin!\n",
  "duration_ms": 133
}
```

### 7.5 Docker Compose Configuration

```yaml
markitdown-api:
  <<: *convert-common
  build:
    context: ./markitdown-api
    dockerfile: Dockerfile
  container_name: markitdown_api
  restart: unless-stopped
  ports:
    - "${MARKITDOWN_PORT:-9100}:9100"
  networks:
    - lyra-net
  environment:
    MARKITDOWN_API_KEY: ${MARKITDOWN_API_KEY:-local-dev-token}
    MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT: ${AZURE_DOC_INTEL_ENDPOINT:-}
    MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_KEY: ${AZURE_DOC_INTEL_KEY:-}
    MARKITDOWN_MAX_FILE_SIZE_MB: ${MARKITDOWN_MAX_FILE_SIZE_MB:-50}
    MARKITDOWN_CONVERSION_TIMEOUT_SECONDS: ${MARKITDOWN_TIMEOUT_SECONDS:-120}
```

> **Important:** All env vars inside the container use the `MARKITDOWN_` prefix because `Settings` uses `env_prefix="MARKITDOWN_"`. The `.env` file uses shorter names (`AZURE_DOC_INTEL_ENDPOINT`, `MARKITDOWN_MAX_FILE_SIZE_MB`, etc.) which are mapped in docker-compose.yml.

### 7.6 `.dockerignore`

Excludes: `__pycache__`, `*.pyc`, `*.pyo`, `*.egg-info`, `.git`, `.gitignore`, `.env`, `.env.*`, `*.md`, `.venv`, `venv/`.

---

## 8. Caddy Reverse Proxy

### 8.1 Overview

- **Image:** `caddy:2-alpine`
- **Container:** `caddy`
- **Profile:** `production` only
- **Ports:** 80 (HTTP redirect), 443 (HTTPS)
- **Volumes:** `Caddyfile` (ro), `caddy-data` (TLS certs + logs), `caddy-config` (autosave)
- **Networks:** `lyra-net`, `postiz-network` (to reach all backend services)

### 8.2 Caddyfile

Three site blocks, one per subdomain:

#### `newsletter.lyrafinai.com`

- `@health path /health` → `respond @health 200` (synthetic health endpoint for Uptime Robot — listmonk has no native health endpoint)
- `reverse_proxy listmonk:9000`
- Security headers: `X-Content-Type-Options nosniff`, `X-Frame-Options DENY`, `Referrer-Policy strict-origin-when-cross-origin`, HSTS (1 year, includeSubDomains, preload)
- Compression: `encode gzip zstd`
- Access logs: `/data/logs/newsletter.access.log` (100MB roll, keep 7)

#### `social.lyrafinai.com`

- `@health path /health` → `respond @health 200` (synthetic health endpoint)
- `reverse_proxy postiz:5000`
- Security headers: `X-Frame-Options SAMEORIGIN` (Postiz needs iframes for some embeds)
- Compression + access logs
- MCP endpoint: `https://social.lyrafinai.com/mcp` — Bearer auth handled by Postiz itself

#### `convert.lyrafinai.com`

- `reverse_proxy markitdown-api:9100`
- Security headers: `X-Frame-Options DENY`, `Referrer-Policy no-referrer`
- Compression + access logs
- Abuse limits: MarkItDown API enforces file size and conversion timeout; Caddy rate limiting would require an additional module/sidecar later

---

## 9. Scripts

### 9.1 `scripts/smoke-local.sh`

Local smoke tests — checks HTTP endpoints for all three profiles.

| Check | URL | Expected |
|---|---|---|
| listmonk | `http://localhost:9001` | 200 |
| Mailpit | `http://localhost:8025` | 200 |
| Postiz | `http://localhost:${POSTIZ_PORT:-5050}` | 200/301/302/307 |
| Temporal UI | `http://localhost:8080/healthz` | 200 |
| MarkItDown | `http://localhost:9100/health` | 200 |

Accepts 301, 302, 307 as pass (Postiz redirects to setup/login on fresh instance).

### 9.2 `scripts/preflight-prod.sh`

Production safety gate for the `docker-compose.prod.yml` deployment path.

**Checks:**

1. Required production secrets are exported by Doppler.
2. Known local placeholders (`change-me`, `local-dev-token`, default DB passwords) are rejected.
3. Postiz registration is closed in production.
4. listmonk SMTP is not pointed at Mailpit.
5. Only Caddy ports 80 and 443 are published publicly.

**Required exported variables:**

`LISTMONK_ADMIN_PASSWORD`, `LISTMONK_DB_PASSWORD`, `POSTIZ_JWT_SECRET`,
`POSTIZ_DB_PASSWORD`, `TEMPORAL_DB_PASSWORD`, `MARKITDOWN_API_KEY`,
`SES_SMTP_HOST`, `SES_SMTP_USER`, `SES_SMTP_PASSWORD`.

Run before every production `up -d`:

```bash
doppler run -- ./scripts/preflight-prod.sh
```

### 9.3 `scripts/backup-postgres.sh`

Backs up all three PostgreSQL databases to `./backups/` (or custom dir).

- Checks if each container is running before backing up
- Uses `pg_dump | gzip` → `listmonk_YYYYMMDD_HHMMSS.sql.gz`, etc.
- Reads DB user/name from environment variables with defaults

### 9.4 `scripts/restore-postgres.sh`

Restores a single database from a backup file.

- Usage: `./scripts/restore-postgres.sh <service> <backup-file>`
- Services: `listmonk`, `postiz`, `temporal`
- **Drops and recreates** the database before restoring (confirmation prompt)
- Checks container is running and backup file exists

### 9.5 `scripts/doctor.sh`

Daily health check script (add to cron: `0 8 * * *`).

Usage: `./scripts/doctor.sh [local|production]`. Local mode skips the
production-only Caddy container; production mode requires it and checks public
health endpoints when it is running.

**Checks:**

1. **Disk usage** — warns at 70%, critical at 85%
2. **Container status** — local mode checks 11 local containers; production mode also requires `caddy`.
3. **Docker log sizes** — inspects `LogPath` for each container
4. **Health endpoints** (if Caddy is running) — checks production URLs, accepts 200/302/307

---

## 10. Runbooks

### 10.1 `runbooks/local-setup.md`

Prerequisites, first-time setup (clone, `.env`, start profiles), smoke tests, MarkItDown API testing, stopping services, viewing logs, backup/restore (local), and env vars for pointing `multiasset-ai` to local services.

### 10.2 `runbooks/contabo-bootstrap.md`

VPS provisioning (Contabo Cloud VPS 10, Ubuntu 24.04), SSH hardening (key-only, no root), UFW firewall (22/80/443), Fail2ban, unattended upgrades, Docker Engine installation, Docker log rotation (`daemon.json`), Doppler CLI setup, repo clone, initial deploy, TLS verification.

**Post-bootstrap checklist:** SSH key login, UFW active, Fail2ban running, Docker log rotation, Doppler configured, all containers healthy, Caddy certs issued, DNS resolves, SSH details in password manager.

### 10.3 `runbooks/deploy.md`

Pre-deployment checklist (local rehearsal, SES access, DNS, OAuth apps, VPS, Doppler), 10-step deployment process, updating services, rolling back, CI/CD notes (future).

**Key command:**

```bash
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production up -d
```

### 10.4 `runbooks/backup-restore.md`

Backup strategy table (daily DB, weekly uploads, weekly VPS snapshot), automated cron backup, manual backup, S3/R2 upload, database restore, uploads restore, restore drill procedure, RTO target (2 hours), secrets recovery.

### 10.5 `runbooks/incident-response.md`

Severity levels (SEV1-SEV4), initial triage steps (container status, doctor, logs, disk, memory), common incidents (container won't start, DB connection failed, Caddy cert issues, ES OOM, disk full, uploads volume full), post-incident steps.

---

## 11. Environment Variables

### 11.1 `.env.example` — Full Template

See `@/.env.example` for the complete template. Key sections:

**General:**

- `TZ` — timezone (default: `Etc/UTC`)

**Email profile:**

- `LISTMONK_PORT`, `LISTMONK_ADMIN_USER`, `LISTMONK_ADMIN_PASSWORD`
- `LISTMONK_DB_USER`, `LISTMONK_DB_PASSWORD`, `LISTMONK_DB_NAME`
- `MAILPIT_SMTP_PORT`
- `SES_SMTP_HOST`, `SES_SMTP_PORT`, `SES_SMTP_USER`, `SES_SMTP_PASSWORD` (production, commented)
- `LISTMONK_BASE_URL`, `LISTMONK_API_USER`, `LISTMONK_API_TOKEN` (for multiasset-ai integration)

**Social profile:**

- `POSTIZ_PORT` (default: 5050 — avoids macOS AirPlay conflict on port 5000)
- `POSTIZ_MAIN_URL`, `POSTIZ_FRONTEND_URL`, `POSTIZ_NEXT_PUBLIC_BACKEND_URL`
- `POSTIZ_JWT_SECRET`, `POSTIZ_DISABLE_REGISTRATION`
- `POSTIZ_DB_USER`, `POSTIZ_DB_PASSWORD`, `POSTIZ_DB_NAME`
- `TEMPORAL_DB_USER`, `TEMPORAL_DB_PASSWORD`
- `LINKEDIN_CLIENT_ID/SECRET`, `FACEBOOK_APP_ID/SECRET`, `YOUTUBE_CLIENT_ID/SECRET`
- `POSTIZ_OPENAI_API_KEY` (optional)
- `POSTIZ_BASE_URL`, `POSTIZ_API_TOKEN` (for multiasset-ai integration)

**Convert profile:**

- `MARKITDOWN_PORT`, `MARKITDOWN_API_KEY`
- `MARKITDOWN_MAX_FILE_SIZE_MB`, `MARKITDOWN_TIMEOUT_SECONDS`
- `AZURE_DOC_INTEL_ENDPOINT`, `AZURE_DOC_INTEL_KEY` (optional)
- `MARKITDOWN_BASE_URL` (for multiasset-ai integration)

**Production only:**

- `NEWSLETTER_DOMAIN`, `SOCIAL_DOMAIN`, `CONVERT_DOMAIN`
- `EMAIL_FROM_ADDRESS`, `EMAIL_FROM_NAME`

### 11.2 Env Var Prefix Mapping

| `.env` / Doppler name | Container env var | Notes |
|---|---|---|
| `AZURE_DOC_INTEL_ENDPOINT` | `MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | Mapped in docker-compose.yml |
| `AZURE_DOC_INTEL_KEY` | `MARKITDOWN_AZURE_DOCUMENT_INTELLIGENCE_KEY` | Mapped in docker-compose.yml |
| `MARKITDOWN_MAX_FILE_SIZE_MB` | `MARKITDOWN_MAX_FILE_SIZE_MB` | Same (passes through) |
| `MARKITDOWN_TIMEOUT_SECONDS` | `MARKITDOWN_CONVERSION_TIMEOUT_SECONDS` | Renamed in docker-compose.yml |
| `SES_SMTP_HOST` | `LISTMONK_smtp__host` | Mapped in docker-compose.prod.yml |
| `SES_SMTP_USER` | `LISTMONK_smtp__username` | Mapped in docker-compose.prod.yml |
| `SES_SMTP_PASSWORD` | `LISTMONK_smtp__password` | Mapped in docker-compose.prod.yml |

---

## 12. Security

### 12.1 API Key Authentication (MarkItDown API)

- `X-API-Key` header required on all conversion endpoints
- Verified via `hmac.compare_digest()` (constant-time comparison)
- Fail-closed: returns 401 if API key is not configured on the server

### 12.2 Path Traversal Prevention (MarkItDown API)

- Filenames sanitized via `os.path.basename()` before writing to temp directory
- Files without extensions are rejected (415)
- Temp directories created with `tempfile.mkdtemp()` and cleaned with `shutil.rmtree()`

### 12.3 Container Security

- MarkItDown API runs as non-root user (`appuser`, UID 1001)
- `.dockerignore` prevents `.env` files from entering build context
- No service ports exposed publicly in production (only Caddy 80/443)
- All databases bound to `127.0.0.1` or internal networks only

### 12.4 Caddy Security Headers

| Header | newsletter | social | convert |
|---|---|---|---|
| `X-Content-Type-Options` | nosniff | nosniff | nosniff |
| `X-Frame-Options` | DENY | SAMEORIGIN | DENY |
| `Referrer-Policy` | strict-origin-when-cross-origin | strict-origin-when-cross-origin | no-referrer |
| `Strict-Transport-Security` | max-age=31536000; includeSubDomains; preload | same | same |

### 12.5 VPS Hardening (Contabo)

- SSH: key-only auth, no root login, `AllowUsers deploy`
- UFW: deny incoming by default, allow 22/80/443 only
- Fail2ban: enabled
- Unattended upgrades: enabled
- Docker log rotation: `max-size: 50m`, `max-file: 5`

### 12.6 Secrets Management

- Doppler CLI for production secrets injection
- `.env` file for local development (gitignored)
- `.env.example` contains only placeholders, never real secrets
- `.gitignore` excludes: `.env`, `.env.local`, `.env.production`, `.doppler/`

### 12.7 Production Safety Gate

`scripts/preflight-prod.sh` is the fail-closed production guard. It must run
before `docker compose ... up -d` in production and verifies:

- Required secret variables are exported by Doppler, not merely present as local `.env` placeholders.
- Secret values are not known placeholders and meet minimum lengths.
- `POSTIZ_DISABLE_REGISTRATION` is `true`; `docker-compose.prod.yml` also hardcodes `DISABLE_REGISTRATION: "true"`.
- Rendered production compose config does not contain `change-me`, `local-dev-token`, or Mailpit SMTP.
- Rendered production compose config does not use SES-incompatible `auth_protocol=cram`.
- Rendered production compose config publishes only ports `80` and `443`.

---

## 13. Testing

### 13.1 Unit Tests (MarkItDown API)

**Location:** `markitdown-api/tests/test_api.py`
**Framework:** pytest + FastAPI TestClient
**Run inside container:** `docker exec markitdown_api python -m pytest tests/ -v`
**Last local container verification:** 2026-06-25, `10 passed`, with only upstream Starlette deprecation warnings.

| Test | Status | Description |
|---|---|---|
| `test_health` | PASS | GET /health returns 200 with status "ok" |
| `test_convert_file_no_api_key` | PASS | POST without X-API-Key returns 401 |
| `test_convert_file_bad_api_key` | PASS | POST with wrong key returns 401 |
| `test_convert_file_unsupported_extension` | PASS | .exe file returns 415 |
| `test_convert_file_oversized` | PASS | 51MB file returns 413 |
| `test_convert_text_file` | PASS | .txt file converts successfully |
| `test_convert_no_extension_rejected` | PASS | File without extension returns 415 |
| `test_convert_generic_mime_fallback` | PASS | CSV with octet-stream MIME converts successfully |
| `test_convert_path_traversal_sanitized` | PASS | `../../../etc/passwd` sanitized, rejected (415) |
| `test_convert_blob_endpoint` | PASS | /v1/convert/blob works identically to /v1/convert/file |

**Total: 10 tests.** Last verified passing on 2026-06-25 inside `markitdown_api`.

### 13.2 Smoke Tests

**Location:** `scripts/smoke-local.sh`
**Checks:** 5 HTTP endpoints across all three profiles
**Accepts:** 200, 301, 302, 307 status codes

### 13.3 Integration Tests (Manual)

Last verified via curl against running containers on 2026-06-25:

- listmonk UI responds (200)
- listmonk healthcheck: healthy
- Mailpit UI responds (200)
- Postiz responds (307 — redirect to setup)
- Postiz healthcheck: healthy
- Temporal UI healthz: `{"status":"OK"}`
- MarkItDown health: `{"status":"ok","azure_doc_intel":false}`
- Auth rejection: 401 without API key
- TXT conversion: 200 with text output
- CSV conversion (generic MIME): 200 with markdown table output
- Bad extension: 415
- No extension: 415
- Path traversal: 415 (sanitized)

### 13.4 Compose Config Validation

Validation commands:

```bash
# Local
docker compose --profile all config --quiet

# Production
LISTMONK_ADMIN_PASSWORD=test-listmonk-admin-password \
LISTMONK_DB_PASSWORD=test-listmonk-db-password \
POSTIZ_JWT_SECRET=test-postiz-jwt-secret-with-32-chars \
POSTIZ_DB_PASSWORD=test-postiz-db-password \
TEMPORAL_DB_PASSWORD=test-temporal-db-password \
MARKITDOWN_API_KEY=test-markitdown-api-key-with-32-chars \
SES_SMTP_HOST=email-smtp.us-east-1.amazonaws.com \
SES_SMTP_USER=test-ses-user \
SES_SMTP_PASSWORD=test-ses-password \
  docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production config --quiet
```

Last verified successfully on 2026-06-25. On 2026-06-27, Docker was not
reachable from this desktop session, so these compose renders were not rerun.

### 13.5 Production Preflight Validation

Expected failure in a local shell with no exported production secrets:

```bash
./scripts/preflight-prod.sh
# [FAIL] LISTMONK_ADMIN_PASSWORD must be exported for production
```

Expected pass with production-shaped exported test values:

```bash
LISTMONK_ADMIN_PASSWORD=local-prod-test-listmonk-admin-pass-123456 \
LISTMONK_DB_PASSWORD=local-prod-test-listmonk-db-pass-123456 \
POSTIZ_JWT_SECRET=local-prod-test-postiz-jwt-secret-1234567890 \
POSTIZ_DB_PASSWORD=local-prod-test-postiz-db-pass-123456 \
TEMPORAL_DB_PASSWORD=local-prod-test-temporal-db-pass-123456 \
MARKITDOWN_API_KEY=local-prod-test-markitdown-api-key-1234567890 \
SES_SMTP_HOST=email-smtp.us-east-1.amazonaws.com \
SES_SMTP_USER=local-prod-test-ses-user \
SES_SMTP_PASSWORD=local-prod-test-ses-password-123456 \
  ./scripts/preflight-prod.sh
```

### 13.6 Last Full Local Docker Validation

Last full runtime validation was completed on 2026-06-25:

- `docker compose --profile all up -d --build`
- `docker compose --profile all ps`
- `./scripts/smoke-local.sh`
- `docker exec markitdown_api python -m pytest tests -q`
- Caddy config validation using `caddy:2-alpine`
- Rendered production config scan confirmed only ports `80` and `443` were published

As of this 2026-06-27 doc refresh, Docker was not available from the current
desktop session, so only file/static checks were refreshed.

---

## 14. Production Deployment

### 14.1 Pre-Deployment Checklist

- [ ] AWS SES production access confirmed (out of sandbox)
- [ ] Cloudflare DNS A records for `newsletter.`, `social.`, `convert.` → VPS IP
- [ ] Doppler project `lyrafin-ops/production` configured with all secrets
- [ ] Contabo VPS provisioned and hardened (see `runbooks/contabo-bootstrap.md`)
- [ ] LinkedIn OAuth app registered (callback: `https://social.lyrafinai.com/connect/linkedin/callback`)
- [ ] Git repo pushed (for `git clone` on VPS)
- [ ] Local rehearsal passed (all smoke tests green)
- [ ] Restore drill completed

### 14.2 Deploy Command

```bash
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production up -d
```

> **Critical:** Always use `-f docker-compose.yml -f docker-compose.prod.yml` to avoid auto-merging `docker-compose.override.yml` (which redirects listmonk SMTP to Mailpit instead of SES).
> Run `scripts/preflight-prod.sh` first so local placeholders, open registration,
> Mailpit SMTP, or unexpected public ports fail before containers start.

### 14.3 Post-Deploy Verification

1. `docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps` — all healthy
2. `docker logs caddy 2>&1 | grep "certificate"` — TLS certs issued
3. `curl -I https://newsletter.lyrafinai.com` — 200/302
4. `curl -I https://social.lyrafinai.com` — 200/302/307
5. `curl https://convert.lyrafinai.com/health` — 200
6. `./scripts/doctor.sh` — all OK
7. Configure listmonk (login, SES settings, create lists)
8. Configure Postiz through the controlled first-run/admin path only; production compose keeps registration disabled
9. Set up Uptime Robot monitors for all three `/health` endpoints

### 14.4 Updating Services

```bash
cd /home/deploy/lyrafin-ops-infra
git pull
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production pull
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production up -d
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps
```

### 14.5 Rolling Back

```bash
# Option 1: Pin previous image tag in docker-compose.yml, then:
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile all --profile production up -d

# Option 2: Restore database from backup
./scripts/restore-postgres.sh <service> ./backups/<service>_<timestamp>.sql.gz
```

---

## 15. Known Decisions & Trade-offs

### 15.1 Docker Compose Profiles vs. Separate Files

**Decision:** Single `docker-compose.yml` with profiles instead of multiple compose files per environment.

**Rationale:** Simpler to maintain, one source of truth, profiles provide clean separation. Override files handle environment-specific differences.

### 15.2 No CI/CD for v1

**Decision:** Manual deployment via SSH + `git pull` + `docker compose up`.

**Rationale:** Deployment cadence is low initially. Add GitHub Actions + SSH deployment when cadence increases.

### 15.3 Local Storage for Postiz Uploads

**Decision:** `STORAGE_PROVIDER=local` with Docker named volume.

**Rationale:** Simplest for v1. Migrate to Cloudflare R2 or AWS S3 when volume exceeds 20 GB or before VPS migration.

### 15.4 No `/v1/convert/url` Endpoint

**Decision:** Intentionally omitted URL-based conversion.

**Rationale:** SSRF risk. Add later with URL allowlisting and validation.

### 15.5 X/Twitter Not Configured in Postiz

**Decision:** X/Twitter social provider is intentionally not configured.

**Rationale:** Handled via Hyperagent native free connector.

### 15.6 Temporal UI Exposed Locally Only

**Decision:** Temporal UI bound to `127.0.0.1:8080`, not exposed via Caddy.

**Rationale:** Temporal UI is for internal debugging only. No authentication layer. Not needed in production via public URL.

### 15.7 Synthetic `/health` Endpoints via Caddy

**Decision:** Caddy responds with 200 for `/health` on `newsletter.` and `social.` domains without proxying to the backend.

**Rationale:** listmonk has no native health endpoint (its `/api/health` requires auth, returns 403). Postiz redirects `/health` to login. Synthetic endpoints allow Uptime Robot monitoring without backend changes.

### 15.8 Postiz Port 5050 for Local Dev

**Decision:** `POSTIZ_PORT=5050` in `.env.example` instead of 5000.

**Rationale:** macOS AirPlay Receiver uses port 5000 by default. Using 5050 avoids the conflict on developer machines.

### 15.9 `docker-compose.prod.yml` Instead of Override

**Decision:** Production overrides in a separate file used with explicit `-f` flags, not as a second override file.

**Rationale:** Docker Compose auto-merges `docker-compose.override.yml`. Using `-f docker-compose.yml -f docker-compose.prod.yml` bypasses the local override, preventing Mailpit SMTP from overriding SES in production.

### 15.10 Non-Root Container for MarkItDown API

**Decision:** MarkItDown API container runs as `appuser` (UID 1001).

**Rationale:** Security best practice — container should not run as root. The `app/` and `tests/` directories are chowned to `appuser:root`.

### 15.11 Local Placeholders Are Allowed Only Behind Preflight

**Decision:** Keep `.env.example` and local setup docs developer-friendly with placeholder values such as `change-me` and `local-dev-token`.

**Rationale:** Local rehearsal should stay easy. Production safety is enforced by `scripts/preflight-prod.sh` plus `docker-compose.prod.yml`, which reject those placeholders before production startup.

---

## Appendix: Container Summary

| Container | Image | Profile | Port (local) | Port (prod) | Network |
|---|---|---|---|---|---|
| `listmonk_app` | `listmonk/listmonk:latest` | email | 9001 | (none) | lyra-net |
| `listmonk_db` | `postgres:17-alpine` | email | 127.0.0.1:5432 | (none) | lyra-net |
| `listmonk_mailpit` | `axllent/mailpit:latest` | email | 8025 | (none) | lyra-net |
| `postiz` | `ghcr.io/gitroomhq/postiz-app:latest` | social | 5050 | (none) | postiz-network, temporal-network |
| `postiz-postgres` | `postgres:17-alpine` | social | (none) | (none) | postiz-network |
| `postiz-redis` | `redis:7.2` | social | (none) | (none) | postiz-network |
| `temporal` | `temporalio/auto-setup:1.28.1` | social | 127.0.0.1:7233 | (none) | temporal-network |
| `temporal-postgresql` | `postgres:16` | social | (none) | (none) | temporal-network |
| `temporal-elasticsearch` | `elasticsearch:7.17.27` | social | internal `expose` only | internal `expose` only | temporal-network |
| `temporal-ui` | `temporalio/ui:2.34.0` | social | 127.0.0.1:8080 | (none) | temporal-network |
| `markitdown_api` | (built from `markitdown-api/Dockerfile`) | convert | 9100 | (none) | lyra-net |
| `caddy` | `caddy:2-alpine` | production | (not used) | 80, 443 | lyra-net, postiz-network |
