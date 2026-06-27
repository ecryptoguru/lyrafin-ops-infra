# Lyrafin Ops Infrastructure

Infrastructure deployment for Lyrafin AI's email, social, and document-conversion stack.

## Services

| Service | Profile | Port | Description |
|---|---|---|---|
| listmonk | email | 9001 | Newsletter + transactional email |
| Mailpit | email | 8025 | Local SMTP testing (dev only) |
| Postiz | social | 5050 | Social media scheduling |
| Temporal | social | 7233 | Workflow engine for Postiz |
| Temporal UI | social | 8080 | Temporal web dashboard |
| MarkItDown API | convert | 9100 | Document-to-markdown conversion |
| Caddy | production | 80/443 | Reverse proxy + TLS |

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your values

# 2. Start a specific profile
docker compose --profile email up -d
docker compose --profile social up -d
docker compose --profile convert up -d --build

# 3. Or start everything
docker compose --profile all up -d

# 4. Run smoke tests
./scripts/smoke-local.sh
```

## Project Structure

```txt
lyrafin-ops-infra/
├── docker-compose.yml          # Main compose with profiles
├── docker-compose.override.yml # Local dev overrides
├── .env.example                # Environment template
├── caddy/
│   └── Caddyfile               # Reverse proxy + TLS config
├── listmonk/
│   ├── config.toml             # Reference config
│   └── README.md
├── postiz/
│   ├── README.md
│   └── dynamicconfig/          # Temporal dynamic config
├── markitdown-api/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── app/                    # FastAPI application
│   └── tests/
├── scripts/
│   ├── backup-postgres.sh
│   ├── restore-postgres.sh
│   ├── smoke-local.sh
│   └── doctor.sh
└── runbooks/
    ├── local-setup.md
    ├── contabo-bootstrap.md
    ├── backup-restore.md
    ├── deploy.md
    └── incident-response.md
```

## Production Domains

- `newsletter.lyrafinai.com` → listmonk
- `social.lyrafinai.com` → Postiz
- `convert.lyrafinai.com` → MarkItDown API

## Secrets Management

Uses [Doppler](https://doppler.com) for secrets injection:

```bash
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production up -d
```

Never commit real secrets to git. Use `.env.example` for local placeholders only.
Production must use `docker-compose.prod.yml`; the preflight rejects placeholder
secrets, open Postiz registration, Mailpit SMTP, and unexpected public ports.

## Source Projects

- [listmonk](https://github.com/knadh/listmonk) — newsletter + email manager
- [Postiz](https://github.com/gitroomhq/postiz-app) — social media scheduler
- [MarkItDown](https://github.com/microsoft/markitdown) — document-to-markdown converter

## Full Plan

See `lyra-ops-final.md` for the complete operating plan, build order, and verification checklist.
