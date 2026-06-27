#!/usr/bin/env bash
set -euo pipefail

# Restore a PostgreSQL backup into the Lyrafin Ops stack
# Usage: ./scripts/restore-postgres.sh <service> <backup-file>
# Example: ./scripts/restore-postgres.sh listmonk ./backups/listmonk_20260101_120000.sql.gz

SERVICE="${1:?Usage: $0 <service> <backup-file>}"
BACKUP_FILE="${2:?Usage: $0 <service> <backup-file>}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

case "$SERVICE" in
    listmonk)
        CONTAINER="listmonk_db"
        DB_USER="${LISTMONK_DB_USER:-listmonk}"
        DB_NAME="${LISTMONK_DB_NAME:-listmonk}"
        ;;
    postiz)
        CONTAINER="postiz-postgres"
        DB_USER="${POSTIZ_DB_USER:-postiz-user}"
        DB_NAME="${POSTIZ_DB_NAME:-postiz-db-local}"
        ;;
    temporal)
        CONTAINER="temporal-postgresql"
        DB_USER="${TEMPORAL_DB_USER:-temporal}"
        DB_NAME="postgres"
        ;;
    *)
        echo "Error: Unknown service '$SERVICE'. Use: listmonk, postiz, or temporal"
        exit 1
        ;;
esac

if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER"; then
    echo "Error: Container '$CONTAINER' is not running."
    exit 1
fi

echo "=== Restoring $SERVICE from $BACKUP_FILE ==="
echo "Container: $CONTAINER"
echo "Database: $DB_NAME"
echo ""

read -rp "This will DROP and recreate the database. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Dropping and recreating database..."
docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";"

echo "Restoring from backup..."
gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"

echo ""
echo "Restore complete for $SERVICE."
