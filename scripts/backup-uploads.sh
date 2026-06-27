#!/usr/bin/env bash
set -euo pipefail

# Backup Docker named volumes (uploads/config) for the Lyrafin Ops stack
# Usage: ./scripts/backup-uploads.sh [backup-dir]
# Default backup dir: ./backups
#
# Backs up the postiz-uploads and listmonk-uploads Docker volumes as gzipped tar
# archives. Schedule WEEKLY (uploads change less often than DB data) alongside
# backup-postgres.sh, and sync the result to AWS S3 / Cloudflare R2.
#
# Cron example (weekly, Sundays at 4am, as deploy user):
#   0 4 * * 0 cd /home/deploy/lyrafin-ops-infra && ./scripts/backup-uploads.sh >> /var/log/lyra-ops-backup-uploads.log 2>&1
#
# Restore with the inverse tar command — see runbooks/backup-restore.md.

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo "=== Lyrafin Ops Volume Backup ==="
echo "Timestamp: $TIMESTAMP"
echo "Backup dir: $BACKUP_DIR"
echo ""

# postiz-uploads volume
if docker volume inspect postiz-uploads >/dev/null 2>&1; then
    echo "Backing up postiz-uploads volume..."
    docker run --rm -v postiz-uploads:/data -v "$BACKUP_DIR":/backup alpine \
        tar czf "/backup/postiz-uploads_${TIMESTAMP}.tar.gz" -C /data .
    echo "  -> postiz-uploads_${TIMESTAMP}.tar.gz"
else
    echo "  [SKIP] postiz-uploads volume not found"
fi

# listmonk-uploads volume
if docker volume inspect listmonk-uploads >/dev/null 2>&1; then
    echo "Backing up listmonk-uploads volume..."
    docker run --rm -v listmonk-uploads:/data -v "$BACKUP_DIR":/backup alpine \
        tar czf "/backup/listmonk-uploads_${TIMESTAMP}.tar.gz" -C /data .
    echo "  -> listmonk-uploads_${TIMESTAMP}.tar.gz"
else
    echo "  [SKIP] listmonk-uploads volume not found"
fi

echo ""
echo "Volume backup complete."
echo "Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/*"${TIMESTAMP}"* 2>/dev/null || echo "  (no files)"
