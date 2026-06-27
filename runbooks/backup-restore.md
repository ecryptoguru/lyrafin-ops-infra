# Backup and Restore Runbook

## Backup Strategy

| Data | Frequency | Method | Destination |
|---|---|---|---|
| listmonk PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Postiz PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Temporal PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Postiz uploads | Weekly | `tar` of Docker volume via script | Local + AWS S3 |
| listmonk uploads | Weekly | `tar` of Docker volume via script | Local + AWS S3 |
| Full VPS snapshot | Weekly | Contabo snapshot | Contabo |

> **Note on VPS snapshots:** if Contabo Auto Backup is not enabled, there is no
> VPS-level safety net. In that case the DB + uploads backups below are the only
> recovery source — make sure the cron runs, S3 syncs succeed, and a restore drill
> has passed *before* relying on them.

## Daily Backup (Automated via Cron)

```bash
# Add to crontab (as deploy user)
0 3 * * * cd /home/deploy/lyrafin-ops-infra && ./scripts/backup-postgres.sh >> /var/log/lyra-ops-backup.log 2>&1
```

## Weekly Volume Backup (Automated via Cron)

Docker volumes (Postiz + listmonk uploads) are not covered by `pg_dump`. Back them
up weekly with `scripts/backup-uploads.sh`:

```bash
# Weekly, Sundays at 4am
0 4 * * 0 cd /home/deploy/lyrafin-ops-infra && ./scripts/backup-uploads.sh >> /var/log/lyra-ops-backup-uploads.log 2>&1
```

## Manual Backup

```bash
cd /home/deploy/lyrafin-ops-infra

# Backup all databases
./scripts/backup-postgres.sh

# Backup uploads volumes (Postiz + listmonk)
./scripts/backup-uploads.sh
```

## Upload to AWS S3

```bash
# Sync backups to S3
aws s3 sync ./backups/ s3://lyrafin-ops-backups/$(date +%Y%m%d)/

# Or use rclone for Cloudflare R2
rclone copy ./backups/ r2:lyrafin-ops-backups/$(date +%Y%m%d)/
```

## Restore Procedure

### Database Restore

```bash
# Restore listmonk
./scripts/restore-postgres.sh listmonk ./backups/listmonk_<timestamp>.sql.gz

# Restore Postiz
./scripts/restore-postgres.sh postiz ./backups/postiz_<timestamp>.sql.gz

# Restore Temporal
./scripts/restore-postgres.sh temporal ./backups/temporal_<timestamp>.sql.gz
```

### Uploads Restore

```bash
# Restore Postiz uploads
docker run --rm -v postiz-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/postiz-uploads_<date>.tar.gz -C /data

# Restore listmonk uploads
docker run --rm -v listmonk-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/listmonk-uploads_<date>.tar.gz -C /data
```

## Restore Drill

> **Run a restore drill into a clean environment *before* going live**, not just
> "when you have time." If VPS snapshots are not enabled, this drill is your proof
> that backups actually work — do not skip it.

```bash
# 1. Stop all services and remove volumes
docker compose --profile all down -v

# 2. Start fresh containers
docker compose --profile all up -d

# 3. Wait for healthy status
docker compose --profile all ps

# 4. Restore databases
./scripts/restore-postgres.sh listmonk ./backups/listmonk_<timestamp>.sql.gz
./scripts/restore-postgres.sh postiz ./backups/postiz_<timestamp>.sql.gz
./scripts/restore-postgres.sh temporal ./backups/temporal_<timestamp>.sql.gz

# 5. Restore uploads
./scripts/restore-postgres.sh # (no-op placeholder; use tar commands below)
docker run --rm -v postiz-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/postiz-uploads_<date>.tar.gz -C /data
docker run --rm -v listmonk-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/listmonk-uploads_<date>.tar.gz -C /data

# 6. Verify data integrity
# - Login to listmonk, check subscriber count
# - Login to Postiz, check scheduled posts
# - Check Temporal UI for workflow history

# 7. Run smoke tests
./scripts/smoke-local.sh
```

## RTO Target

- **Estimated RTO:** 2 hours from backup
- This assumes: S3 backup available, VPS accessible, Docker installed
- Without VPS snapshots, RTO may be longer (full VPS rebuild + Docker install + restore)
- Re-evaluate at 500+ users or first B2B SLA commitment

## Secrets Recovery

If Doppler is unavailable:
1. Check 1Password/Bitwarden for Contabo SSH access, Doppler service tokens, and provider OAuth credentials
2. Restore Doppler access: `doppler login` → select `lyrafin-ops/production`
3. If Doppler account is lost: use stored service token to re-authenticate
