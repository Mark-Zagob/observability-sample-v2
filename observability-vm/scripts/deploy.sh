#!/bin/bash
# ============================================================
# Deploy Script — Restart services + tạo Grafana annotation
# ============================================================
# Usage:
#   ./deploy.sh phase1          → Restart phase1 + annotation
#   ./deploy.sh phase3          → Restart phase3 + annotation
#   ./deploy.sh all             → Restart tất cả phases
#   ./deploy.sh phase1 "Fix alerting config"  → Custom message
# ============================================================

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin123}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Gửi annotation tới Grafana
# ============================================================
create_annotation() {
  local phase="$1"
  local message="${2:-Deploy $phase}"
  local timestamp_ms=$(($(date +%s) * 1000))

  echo -e "${BLUE}📌 Creating Grafana annotation...${NC}"

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "${GRAFANA_URL}/api/annotations" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d "{
      \"time\": ${timestamp_ms},
      \"tags\": [\"deploy\", \"${phase}\"],
      \"text\": \"🚀 ${message}\"
    }" 2>/dev/null) || true

  local http_code
  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}✅ Annotation created: ${message}${NC}"
  else
    echo -e "${YELLOW}⚠️  Could not create annotation (Grafana may not be ready)${NC}"
  fi
}

# ============================================================
# Restart phase
# ============================================================
restart_phase() {
  local phase="$1"
  local dir=""

  case "$phase" in
    phase1|metrics)
      dir="$BASE_DIR/../phase1-metrics"
      phase="phase1-metrics"
      ;;
    phase2|logging)
      dir="$BASE_DIR/../phase2-logging"
      phase="phase2-logging"
      ;;
    phase3|tracing)
      dir="$BASE_DIR/../phase3-tracing"
      phase="phase3-tracing"
      ;;
    storage|minio)
      dir="$BASE_DIR/../storage"
      phase="storage"
      ;;
    all)
      restart_phase storage
      restart_phase phase1
      restart_phase phase2
      restart_phase phase3
      return
      ;;
    *)
      echo "Unknown phase: $phase"
      echo "Usage: $0 {phase1|phase2|phase3|storage|all} [message]"
      exit 1
      ;;
  esac

  echo -e "${GREEN}🔄 Restarting ${phase}...${NC}"
  docker compose -f "$dir/docker-compose.yml" down
  docker compose -f "$dir/docker-compose.yml" up -d
  echo -e "${GREEN}✅ ${phase} is up${NC}"
}

# ============================================================
# Main
# ============================================================
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 {phase1|phase2|phase3|storage|all} [message]"
  exit 1
fi

PHASE="$1"
MESSAGE="${2:-Deploy ${PHASE}}"

restart_phase "$PHASE"

# Đợi Grafana ready (chỉ khi restart phase1 hoặc all)
if [[ "$PHASE" == "phase1" || "$PHASE" == "metrics" || "$PHASE" == "all" ]]; then
  echo -e "${YELLOW}⏳ Waiting for Grafana to be ready...${NC}"
  for i in $(seq 1 30); do
    if curl -s "${GRAFANA_URL}/api/health" | grep -q "ok" 2>/dev/null; then
      break
    fi
    sleep 2
  done
fi

create_annotation "$PHASE" "$MESSAGE"

echo ""
echo -e "${GREEN}🎉 Done! Check Grafana dashboards for the deploy marker.${NC}"
