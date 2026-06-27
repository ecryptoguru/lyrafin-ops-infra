# Deployment Runbook

## Pre-Deployment Checklist

- [ ] Local rehearsal passed (all smoke tests green)
- [ ] Restore drill completed successfully
- [ ] AWS SES production access confirmed (for email cutover)
- [ ] Cloudflare DNS configured for three subdomains
- [ ] LinkedIn developer app registered (for Postiz OAuth)
- [ ] Contabo VPS provisioned and hardened (see `contabo-bootstrap.md`)
- [ ] Doppler CLI configured on VPS with `lyrafin-ops/production` project

## Deployment Steps (v1)

### Step 1: Pull latest code

```bash
cd /home/deploy/lyrafin-ops-infra
git pull
```

### Step 2: Pull latest images

```bash
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production pull
```

### Step 3: Run production preflight

```bash
doppler run -- ./scripts/preflight-prod.sh
```

The preflight must pass before starting containers. It rejects local placeholder
secrets, open Postiz registration, Mailpit SMTP, and public ports other than 80/443.

### Step 4: Start all services

```bash
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production up -d
```

> **Important:** Always use `-f docker-compose.yml -f docker-compose.prod.yml` to avoid
> auto-merging `docker-compose.override.yml` (which is for local dev only and would
> redirect listmonk SMTP to Mailpit instead of SES).

### Step 5: Verify all containers are healthy

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps
```

All containers should show `Up (healthy)`.

### Step 6: Verify Caddy TLS

```bash
docker logs caddy 2>&1 | grep "certificate obtained"
```

### Step 7: Test endpoints

```bash
curl -I https://newsletter.lyrafinai.com
curl -I https://social.lyrafinai.com
curl https://convert.lyrafinai.com/health
```

### Step 8: Run doctor check

```bash
./scripts/doctor.sh
```

### Step 9: Configure listmonk

1. Login to `https://newsletter.lyrafinai.com` with admin credentials
2. Configure SES SMTP settings (if not already via env vars)
3. Create initial lists: `blog_subscribers`, `product_updates`, `trial_onboarding`, `reengagement`, `creator_referrals`, `internal_test`
4. Send a test email to `internal_test` list

### Step 10: Configure Postiz

1. Login to `https://social.lyrafinai.com`
2. Create the admin account through the controlled first-run path only
3. Keep production `DISABLE_REGISTRATION=true`; `docker-compose.prod.yml` enforces it
4. Connect social providers (LinkedIn first, then Facebook/Instagram)
5. Test scheduling a draft post

### Step 11: Set up monitoring

Configure Uptime Robot monitors:
- `https://newsletter.lyrafinai.com/health`
- `https://social.lyrafinai.com/health`
- `https://convert.lyrafinai.com/health`
- Main Lyrafin app URL

Set alert email to `ankit@lyrafinai.com`.

## Updating Services

```bash
cd /home/deploy/lyrafin-ops-infra
git pull
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production pull
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production up -d
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps
```

## Rolling Back

If a new image causes issues:

```bash
# Option 1: Revert to previous image tag
# Edit docker-compose.yml to pin a specific version tag instead of :latest
# Then:
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production up -d

# Option 2: Restore database from backup
./scripts/restore-postgres.sh <service> ./backups/<service>_<timestamp>.sql.gz
```

## CI/CD (Future)

No automated CI/CD for v1. Add GitHub Actions + SSH deployment in a later iteration when deployment cadence increases.
