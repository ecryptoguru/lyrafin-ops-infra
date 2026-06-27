# Incident Response Runbook

## Severity Levels

| Level | Description | Response Time |
|---|---|---|
| SEV1 | Full outage — all services down | Immediate |
| SEV2 | Partial outage — one service down | 30 min |
| SEV3 | Degraded — service slow or feature broken | 2 hours |
| SEV4 | Minor — cosmetic or non-critical issue | Next business day |

## Initial Triage

1. **Check container status:**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps
   ```

2. **Run doctor check:**
   ```bash
   ./scripts/doctor.sh production
   ```

3. **Check recent logs:**
   ```bash
   docker compose logs --tail=100 <service-name>
   ```

4. **Check disk space:**
   ```bash
   df -h /
   ```

5. **Check memory:**
   ```bash
   free -h
   ```

## Common Incidents

### Container Won't Start

```bash
# Check logs for the failing container
docker logs <container-name> --tail=200

# Common causes:
# - Database not ready (check depends_on healthcheck)
# - Missing env vars (verify Doppler config)
# - Port conflict (check: sudo lsof -i :<port>)
# - Volume permission issues
```

### Database Connection Failed

```bash
# Check if Postgres is healthy
docker exec <db-container> pg_isready -U <db-user>

# Check Postgres logs
docker logs <db-container> --tail=100

# If database is corrupted, restore from backup:
./scripts/restore-postgres.sh <service> ./backups/<latest-backup>.sql.gz
```

### Caddy Certificate Issues

```bash
# Check Caddy logs for cert errors
docker logs caddy 2>&1 | grep -i "error\|certificate"

# Force certificate renewal
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# Check DNS resolution
dig newsletter.lyrafinai.com
dig social.lyrafinai.com
dig convert.lyrafinai.com
```

### Elasticsearch Out of Memory

```bash
# Check ES health
curl http://localhost:9200/_cluster/health

# If ES is down, increase memory:
# Edit docker-compose.yml: ES_JAVA_OPTS=-Xms512m -Xmx512m
# Then restart:
docker compose --profile social up -d temporal-elasticsearch
```

### Disk Full

```bash
# Check Docker disk usage
docker system df

# Clean up unused images/containers
docker system prune -a --volumes
# WARNING: only run --volumes if you know which volumes to remove

# Check log sizes
du -sh /var/lib/docker/containers/*/*.log

# Rotate logs manually
truncate -s 0 /var/lib/docker/containers/*/*-json.log
```

### Postiz Uploads Volume Full

```bash
# Check volume size
docker system df -v | grep postiz-uploads

# If exceeding 20 GB, plan migration to Cloudflare R2 or AWS S3
# See: lyra-ops-final.md → Media / Upload Storage section
```

## Post-Incident

1. Document the incident: timeline, root cause, resolution
2. Update this runbook with any new troubleshooting steps
3. Add monitoring alerts for the failure mode
4. Run a restore drill if data loss occurred
