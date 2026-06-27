#!/usr/bin/env bash
set -euo pipefail

# Smoke test for local Lyrafin Ops services
# Usage: ./scripts/smoke-local.sh

echo "=== Lyrafin Ops Local Smoke Test ==="
echo ""

FAIL=0

check() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$status_code" = "$expected" ] || [ "$status_code" = "302" ] || [ "$status_code" = "301" ] || [ "$status_code" = "307" ]; then
        echo "  [PASS] $name ($url) -> $status_code"
    else
        echo "  [FAIL] $name ($url) -> $status_code (expected $expected)"
        FAIL=1
    fi
}

echo "Email profile:"
check "listmonk" "http://localhost:9001"
check "Mailpit" "http://localhost:8025"

echo ""
echo "Social profile:"
check "Postiz" "http://localhost:${POSTIZ_PORT:-5050}"
check "Temporal UI" "http://localhost:8080/healthz"

echo ""
echo "Convert profile:"
check "MarkItDown health" "http://localhost:9100/health"

echo ""
if [ "$FAIL" = "0" ]; then
    echo "All smoke tests passed."
else
    echo "Some smoke tests failed. Check service logs with: docker compose logs <service>"
    exit 1
fi
