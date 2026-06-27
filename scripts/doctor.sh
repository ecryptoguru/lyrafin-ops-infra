#!/usr/bin/env bash
set -euo pipefail

# Doctor — daily health check for the Lyrafin Ops stack
# Usage: ./scripts/doctor.sh [local|production]
# Add to cron: 0 8 * * * /path/to/lyrafin-ops-infra/scripts/doctor.sh

DISK_THRESHOLD_WARN=70
DISK_THRESHOLD_CRIT=85
MODE="${1:-local}"

echo "=== Lyrafin Ops Doctor ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Mode: $MODE"
echo ""

# Check disk usage
echo "Disk usage:"
df -h / | awk 'NR>1 {
    usage=$5;
    gsub(/%/,"",usage);
    if (usage+0 >= '"$DISK_THRESHOLD_CRIT"') print "  [CRITICAL] / at " $5 " used — immediate action required";
    else if (usage+0 >= '"$DISK_THRESHOLD_WARN"') print "  [WARN] / at " $5 " used — plan cleanup";
    else print "  [OK] / at " $5 " used";
}'
echo ""

# Check running containers
echo "Container status:"
EXPECTED_CONTAINERS=(
    "listmonk_app"
    "listmonk_db"
    "listmonk_mailpit"
    "postiz"
    "postiz-postgres"
    "postiz-redis"
    "temporal"
    "temporal-postgresql"
    "temporal-elasticsearch"
    "temporal-ui"
    "markitdown_api"
)

if [ "$MODE" = "production" ]; then
    EXPECTED_CONTAINERS+=("caddy")
fi

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  [OK] $container running"
    else
        echo "  [WARN] $container not running"
    fi
done
if [ "$MODE" != "production" ]; then
    echo "  [SKIP] caddy production profile not expected in local mode"
fi
echo ""

# Check Docker log disk usage
echo "Docker log sizes:"
for container in "${EXPECTED_CONTAINERS[@]}"; do
    log_path=$(docker inspect --format='{{.LogPath}}' "$container" 2>/dev/null || true)
    if [ -n "$log_path" ] && [ -f "$log_path" ]; then
        size=$(du -sh "$log_path" 2>/dev/null | cut -f1)
        echo "  $container: $size"
    fi
done
echo ""

# Check health endpoints (if Caddy is running)
if docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
    echo "Health endpoints:"
    for url in \
        "https://newsletter.lyrafinai.com" \
        "https://social.lyrafinai.com" \
        "https://convert.lyrafinai.com/health"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
        if [ "$status" = "200" ] || [ "$status" = "302" ] || [ "$status" = "307" ]; then
            echo "  [OK] $url -> $status"
        else
            echo "  [FAIL] $url -> $status"
        fi
    done
    echo ""
fi

echo "Doctor check complete."
