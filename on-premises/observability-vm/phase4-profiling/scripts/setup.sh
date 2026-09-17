#!/bin/bash
# ============================================================
# Phase 4.5 Setup Script — Pyroscope Datasource Provisioning
# ============================================================
# Purpose: Copy Pyroscope datasource config into Grafana's
#          provisioning directory so it's auto-loaded on startup.
#
# Why this script?
#   - Grafana runs in phase1-metrics, mounts its own provisioning dir
#   - Phase 4.5 datasource config lives in phase4-profiling dir
#   - This script copies the config file to the right place
#   - Then restarts Grafana to pick up the new datasource
#
# Usage:
#   bash setup.sh          # Run from phase4-profiling directory
#   bash setup.sh --dry-run # Preview what would happen
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE4_DIR="$(dirname "$SCRIPT_DIR")"
PHASE1_DIR="$PHASE4_DIR/../phase1-metrics"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Preflight Checks
# ============================================================
echo -e "${BLUE}🔍 Preflight checks...${NC}"

# Check phase1-metrics exists
if [ ! -d "$PHASE1_DIR" ]; then
    echo -e "${RED}❌ Error: phase1-metrics directory not found at $PHASE1_DIR${NC}"
    exit 1
fi

# Check Grafana provisioning dir exists
GRAFANA_PROV_DIR="$PHASE1_DIR/grafana/provisioning/datasources"
if [ ! -d "$GRAFANA_PROV_DIR" ]; then
    echo -e "${RED}❌ Error: Grafana provisioning directory not found${NC}"
    exit 1
fi

# Check pyroscope datasource exists
PYROSCOPE_DS="$SCRIPT_DIR/../grafana/provisioning/datasources/pyroscope.yml"
if [ ! -f "$PYROSCOPE_DS" ]; then
    echo -e "${RED}❌ Error: pyroscope.yml not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Preflight checks passed${NC}"
echo ""

# ============================================================
# Dry Run Mode
# ============================================================
if [[ "${1:-}" == "--dry-run" ]]; then
    echo -e "${YELLOW}🔎 DRY RUN — no changes will be made${NC}"
    echo ""
    echo "Would copy:"
    echo "  FROM: $PYROSCOPE_DS"
    echo "  TO:   $GRAFANA_PROV_DIR/pyroscope.yml"
    echo ""
    echo "Would restart Grafana container to reload datasources."
    exit 0
fi

# ============================================================
# Backup existing datasource (if any)
# ============================================================
DEST_FILE="$GRAFANA_PROV_DIR/pyroscope.yml"
if [ -f "$DEST_FILE" ]; then
    BACKUP_FILE="$DEST_FILE.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}⚠️  Existing datasource found, backing up...${NC}"
    cp "$DEST_FILE" "$BACKUP_FILE"
    echo "  Backup: $BACKUP_FILE"
fi

# ============================================================
# Copy Datasource Config
# ============================================================
echo -e "${BLUE}📋 Copying Pyroscope datasource config...${NC}"
cp "$PYROSCOPE_DS" "$DEST_FILE"
echo -e "${GREEN}✅ Copied to: $DEST_FILE${NC}"
echo ""

# ============================================================
# Restart Grafana to Reload Datasources
# ============================================================
echo -e "${BLUE}🔄 Restarting Grafana to load new datasource...${NC}"
cd "$PHASE1_DIR"

# Check if Grafana is running
if docker compose ps grafana 2>/dev/null | grep -q "Up"; then
    docker compose restart grafana
    echo -e "${GREEN}✅ Grafana restarted${NC}"
else
    echo -e "${YELLOW}⚠️  Grafana not running. You may need to start phase1-metrics first.${NC}"
    echo "  Run: cd $PHASE1_DIR && docker compose up -d"
fi

# ============================================================
# Verification
# ============================================================
echo ""
echo -e "${BLUE}🔍 Waiting for Grafana to be ready...${NC}"
sleep 5
for i in $(seq 1 30); do
    if curl -s "http://localhost:3000/api/health" 2>/dev/null | grep -q "ok"; then
        echo -e "${GREEN}✅ Grafana is ready${NC}"
        break
    fi
    sleep 2
done

# Verify Pyroscope datasource
echo ""
echo -e "${BLUE}🔍 Verifying Pyroscope datasource...${NC}"
if curl -s -u "admin:admin123" "http://localhost:3000/api/datasources/name/Pyroscope" 2>/dev/null | grep -q "pyroscope"; then
    echo -e "${GREEN}✅ Pyroscope datasource is configured in Grafana${NC}"
    echo ""
    echo -e "${GREEN}🎉 Setup complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start Pyroscope: cd $PHASE4_DIR && docker compose up -d"
    echo "  2. Instrument services (see profiling_setup.py)"
    echo "  3. Open Grafana → Explore → select 'Pyroscope' datasource"
    echo "  4. Try flame graphs!"
else
    echo -e "${YELLOW}⚠️  Datasource not found. Check Grafana logs or restart manually.${NC}"
fi
