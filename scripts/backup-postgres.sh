#!/usr/bin/env bash
set -euo pipefail

# Backup all PostgreSQL databases in the Lyrafin Ops stack
# Usage: ./scripts/backup-postgres.sh [backup-dir]
# Default backup dir: ./backups

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo "=== Lyrafin Ops PostgreSQL Backup ==="
echo "Timestamp: $TIMESTAMP"
echo "Backup dir: $BACKUP_DIR"
echo ""

# listmonk database
if docker ps --format '{{.Names}}' | grep -q "listmonk_db"; then
    echo "Backing up listmonk database..."
    docker exec listmonk_db pg_dump -U "${LISTMONK_DB_USER:-listmonk}" "${LISTMONK_DB_NAME:-listmonk}" \
        | gzip > "$BACKUP_DIR/listmonk_${TIMESTAMP}.sql.gz"
    echo "  -> listmonk_${TIMESTAMP}.sql.gz"
fi

# Postiz database
if docker ps --format '{{.Names}}' | grep -q "postiz-postgres"; then
    echo "Backing up Postiz database..."
    docker exec postiz-postgres pg_dump -U "${POSTIZ_DB_USER:-postiz-user}" "${POSTIZ_DB_NAME:-postiz-db-local}" \
        | gzip > "$BACKUP_DIR/postiz_${TIMESTAMP}.sql.gz"
    echo "  -> postiz_${TIMESTAMP}.sql.gz"
fi

# Temporal database
if docker ps --format '{{.Names}}' | grep -q "temporal-postgresql"; then
    echo "Backing up Temporal database..."
    docker exec temporal-postgresql pg_dump -U "${TEMPORAL_DB_USER:-temporal}" postgres \
        | gzip > "$BACKUP_DIR/temporal_${TIMESTAMP}.sql.gz"
    echo "  -> temporal_${TIMESTAMP}.sql.gz"
fi

echo ""
echo "Backup complete."
echo "Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/*"${TIMESTAMP}"* 2>/dev/null || echo "  (no files)"
