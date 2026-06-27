# Postiz Configuration Notes

## Docker Compose

Postiz is deployed as part of the `social` profile in `docker-compose.yml`.
The official `ghcr.io/gitroomhq/postiz-app:latest` image is used.

## Required Services

- **postiz** — the main application (port 5000 internally, exposed on $POSTIZ_PORT)
- **postiz-postgres** — PostgreSQL 17 for Postiz app data
- **postiz-redis** — Redis 7.2 for caching/queues
- **temporal** — Temporal workflow engine (auto-setup image)
- **temporal-postgresql** — separate PostgreSQL 16 for Temporal
- **temporal-elasticsearch** — Elasticsearch 7.17 for Temporal visibility
- **temporal-ui** — optional Temporal web UI (port 8080, localhost only)

## Key Configuration

| Variable | Value | Notes |
|---|---|---|
| `IS_GENERAL` | `true` | Required for self-hosted routing |
| `DISALLOW_PLUS` | `true` | Hides cloud billing UI |
| `DISABLE_REGISTRATION` | `true` (after first signup) | Prevent public registration |
| `STORAGE_PROVIDER` | `local` | Local Docker volume for v1 |
| `UPLOAD_DIRECTORY` | `/uploads` | Mapped to `postiz-uploads` volume |

## Social Provider Configuration

**First priority (register OAuth apps before deployment):**
- LinkedIn — callback: `https://social.lyrafinai.com/connect/linkedin/callback`
- Facebook/Instagram — Meta Developer app

**Secondary:**
- YouTube

**NOT via Postiz:**
- X/Twitter — handled by Hyperagent native free connector

## Postiz MCP Server

Postiz exposes an MCP server for agent integration:
```
URL: https://social.lyrafinai.com/mcp
Header: Authorization: Bearer {POSTIZ_API_KEY}
Transport: Streamable HTTP
```

Get the API key from: Postiz Settings → Developers → Public API.

## Uploads

Uploads are stored in the `postiz-uploads` Docker named volume.
Migrate to Cloudflare R2 or AWS S3 when volume exceeds 20 GB or before VPS migration.
