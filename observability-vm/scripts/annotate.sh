#!/bin/bash
# ============================================================
# Annotate — Tạo deploy marker trên Grafana mà không restart
# ============================================================
# Usage:
#   ./annotate.sh "Release v2.0"
#   ./annotate.sh "Hotfix payment timeout" payment
#   ./annotate.sh "DB migration started" database warning
# ============================================================

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin123}"

MESSAGE="${1:-Manual annotation}"
TAG="${2:-deploy}"
EXTRA_TAG="${3:-}"

TAGS="\"${TAG}\""
[[ -n "$EXTRA_TAG" ]] && TAGS="\"${TAG}\", \"${EXTRA_TAG}\""

TIMESTAMP_MS=$(($(date +%s) * 1000))

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${GRAFANA_URL}/api/annotations" \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d "{
    \"time\": ${TIMESTAMP_MS},
    \"tags\": [${TAGS}],
    \"text\": \"📌 ${MESSAGE}\"
  }")

if [[ "$RESPONSE" == "200" ]]; then
  echo "✅ Annotation created: ${MESSAGE}"
else
  echo "❌ Failed (HTTP ${RESPONSE}). Is Grafana running?"
fi
