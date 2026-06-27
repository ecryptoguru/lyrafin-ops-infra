#!/usr/bin/env bash
set -euo pipefail

# Production safety gate for the Contabo/Doppler deployment path.
# Run with production secrets exported, for example:
#   doppler run -- ./scripts/preflight-prod.sh

COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.prod.yml)
PROFILES=(--profile all --profile production)

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

required_vars=(
    LISTMONK_ADMIN_PASSWORD
    LISTMONK_DB_PASSWORD
    POSTIZ_JWT_SECRET
    POSTIZ_DB_PASSWORD
    TEMPORAL_DB_PASSWORD
    MARKITDOWN_API_KEY
    SES_SMTP_HOST
    SES_SMTP_USER
    SES_SMTP_PASSWORD
)

secret_vars=(
    LISTMONK_ADMIN_PASSWORD
    LISTMONK_DB_PASSWORD
    POSTIZ_JWT_SECRET
    POSTIZ_DB_PASSWORD
    TEMPORAL_DB_PASSWORD
    MARKITDOWN_API_KEY
    SES_SMTP_PASSWORD
)

for var in "${required_vars[@]}"; do
    value="${!var:-}"
    if [ -z "$value" ]; then
        fail "$var must be exported for production"
    fi
done

for var in "${secret_vars[@]}"; do
    value="${!var:-}"
    case "$value" in
        change-me|change-me-to-a-long-random-string|local-dev-token|listmonk|postiz-password|temporal)
            fail "$var uses an insecure placeholder value"
            ;;
    esac

    if [ "${#value}" -lt 16 ]; then
        fail "$var must be at least 16 characters"
    fi
done

if [ "${#POSTIZ_JWT_SECRET}" -lt 32 ]; then
    fail "POSTIZ_JWT_SECRET must be at least 32 characters"
fi

if [ "${#MARKITDOWN_API_KEY}" -lt 32 ]; then
    fail "MARKITDOWN_API_KEY must be at least 32 characters"
fi

if [ "${POSTIZ_DISABLE_REGISTRATION:-true}" != "true" ]; then
    fail "POSTIZ_DISABLE_REGISTRATION must be true for production"
fi

rendered_config="$(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" config)"

if grep -Eq 'change-me|change-me-to-a-long-random-string|local-dev-token' <<<"$rendered_config"; then
    fail "rendered production compose config still contains an insecure placeholder"
fi

if grep -Eq 'DISABLE_REGISTRATION: "?false"?' <<<"$rendered_config"; then
    fail "rendered production compose config leaves Postiz registration enabled"
fi

if grep -Eq 'LISTMONK_smtp__host: "?mailpit"?' <<<"$rendered_config"; then
    fail "rendered production compose config points listmonk SMTP at Mailpit"
fi

published_ports="$(awk '/published:/{gsub(/"/, "", $2); print $2}' <<<"$rendered_config" | sort -u)"
while IFS= read -r port; do
    [ -z "$port" ] && continue
    case "$port" in
        80|443)
            ;;
        *)
            fail "unexpected production published port: $port"
            ;;
    esac
done <<<"$published_ports"

echo "[PASS] production preflight passed"
