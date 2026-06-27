# Backup and Restore Runbook

## Backup Strategy

| Data | Frequency | Method | Destination |
|---|---|---|---|
| listmonk PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Postiz PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Temporal PostgreSQL | Daily | `pg_dump` via script | Local + AWS S3 |
| Postiz uploads | Weekly | `tar` of Docker volume | Local + AWS S3 |
| listmonk uploads | Weekly | `tar` of Docker volume | Local + AWS S3 |
| Full VPS snapshot | Weekly | Contabo snapshot | Contabo |

## Daily Backup (Automated via Cron)

```bash
# Add to crontab (as deploy user)
0 3 * * * cd /home/deploy/lyrafin-ops-infra && ./scripts/backup-postgres.sh >> /var/log/lyra-ops-backup.log 2>&1
```

## Manual Backup

```bash
cd /home/deploy/lyrafin-ops-infra

# Backup all databases
./scripts/backup-postgres.sh

# Backup uploads (Postiz)
docker run --rm -v postiz-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar czf /backup/postiz-uploads_$(date +%Y%m%d).tar.gz -C /data .

# Backup uploads (listmonk)
docker run --rm -v listmonk-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar czf /backup/listmonk-uploads_$(date +%Y%m%d).tar.gz -C /data .
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

Run restore drills into a clean Docker environment before relying on backups:

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
docker run --rm -v postiz-uploads:/data -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/postiz-uploads_<date>.tar.gz -C /data

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
- Re-evaluate at 500+ users or first B2B SLA commitment

## Secrets Recovery

If Doppler is unavailable:
1. Check 1Password/Bitwarden for Contabo SSH access, Doppler service tokens, and provider OAuth credentials
2. Restore Doppler access: `doppler login` → select `lyrafin-ops/production`
3. If Doppler account is lost: use stored service token to re-authenticate
