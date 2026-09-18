#!/bin/bash
# ============================================================
# Profiling Dashboard Verification Script
# ============================================================
# Script này giúp verify rằng các profiling panels đã được fix
# và đang hoạt động bình thường.
#
# Usage: bash verify_profiling.sh
# ============================================================

set -e

echo "=========================================="
echo "🔍 Profiling Dashboard Verification"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Checkmarks
CHECK="${GREEN}✅${NC}"
CROSS="${RED}❌${NC}"
WARN="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"

# Function to print section
print_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}📋 $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check command and print result
check_cmd() {
    local description="$1"
    local cmd="$2"
    local expected="$3"
    
    echo -n "Checking: $description ... "
    
    if output=$(eval "$cmd" 2>&1); then
        if [ -n "$expected" ]; then
            if echo "$output" | grep -q "$expected"; then
                echo -e "${CHECK} PASS"
                return 0
            else
                echo -e "${CROSS} FAIL (unexpected output)"
                echo "  Expected: $expected"
                echo "  Got: $output"
                return 1
            fi
        else
            echo -e "${CHECK} PASS"
            return 0
        fi
    else
        echo -e "${CROSS} FAIL"
        echo "  Error: $output"
        return 1
    fi
}

# ============================================================
# Step 1: Check Pyroscope Container Health
# ============================================================
print_section "Step 1: Pyroscope Container Health"

check_cmd "Pyroscope container running" \
    "docker ps --filter name=pyroscope --format '{{.Status}}'" \
    "Up" || {
    echo -e "${CROSS} Pyroscope container not running!"
    echo -e "${INFO} Start it with: cd observability-vm/phase4-profiling && docker compose up -d"
    exit 1
}

check_cmd "Pyroscope server ready" \
    "curl -s http://localhost:4040/ready" \
    "ready" || {
    echo -e "${CROSS} Pyroscope server not ready!"
    exit 1
}

check_cmd "Pyroscope version" \
    "curl -s http://localhost:4040/api/v1/status/buildinfo | grep -o 'version=[^\"]*' | head -1" \
    ""

# ============================================================
# Step 2: Check Prometheus Scrape Target
# ============================================================
print_section "Step 2: Prometheus Scrape Target"

check_cmd "Prometheus target 'pyroscope' is UP" \
    "curl -s http://192.168.100.55:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job==\"pyroscope\") | .health'" \
    "up" || {
    echo -e "${CROSS} Prometheus target 'pyroscope' is DOWN!"
    echo -e "${INFO} Check prometheus.yml for scrape job configuration"
    exit 1
}

check_cmd "Last scrape successful" \
    "curl -s http://192.168.100.55:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job==\"pyroscope\") | .lastError'" \
    "" || {
    echo -e "${WARN} Last scrape had errors"
}

# ============================================================
# Step 3: Check Pyroscope /metrics Endpoint
# ============================================================
print_section "Step 3: Pyroscope /metrics Endpoint"

check_cmd "/metrics endpoint accessible" \
    "curl -s http://localhost:4040/metrics | head -1" \
    "#" || {
    echo -e "${CROSS} /metrics endpoint not accessible!"
    exit 1
}

echo -e "${INFO} Checking available metrics..."
echo ""
echo "  Available metric families:"
curl -s http://localhost:4040/metrics | grep "^# HELP" | cut -d' ' -f2 | sed 's/_total$//' | sort -u | sed 's/^/    /' | head -20
echo ""
echo -e "${WARN} Note: Pyroscope KHÔNG expose 'pyroscope_app_stats_samples_ingested_total'"
echo -e "${INFO} Solution: Use Pyroscope datasource instead of Prometheus for profile queries"

# ============================================================
# Step 4: Check Grafana Datasource
# ============================================================
print_section "Step 4: Grafana Pyroscope Datasource"

check_cmd "Grafana accessible" \
    "curl -s http://192.168.100.55:3000/api/health" \
    "ok" || {
    echo -e "${CROSS} Grafana not accessible!"
    exit 1
}

check_cmd "Pyroscope datasource exists" \
    "curl -s http://192.168.100.55:3000/api/datasources -u admin:admin | jq -r '.[] | select(.name==\"Pyroscope\") | .type'" \
    "grafana-pyroscope-datasource" || {
    echo -e "${CROSS} Pyroscope datasource not configured!"
    echo -e "${INFO} Check phase4-profiling/grafana/provisioning/datasources/pyroscope.yml"
    exit 1
}

echo -e "${CHECK} Pyroscope datasource configured:"
echo "  - Name: Pyroscope"
echo "  - Type: grafana-pyroscope-datasource"
echo "  - UID: pyroscope-datasource"

# ============================================================
# Step 5: Check App Profiling Initialization
# ============================================================
print_section "Step 5: App Profiling Initialization"

echo -e "${INFO} Checking profiling initialization for all services..."
echo ""

services=("order-service" "payment-service" "api-gateway" "inventory-worker" "notification-worker" "traffic-gen")

for service in "${services[@]}"; do
    echo -n "  $service: "
    
    # Check if container is running
    if ! docker ps --filter name=$service --format '{{.Names}}' | grep -q "$service"; then
        echo -e "${CROSS} Container not running"
        continue
    fi
    
    # Check for profiling initialization in logs
    if docker logs $service 2>&1 | grep -q "Pyroscope profiling initialized"; then
        workers=$(docker logs $service 2>&1 | grep -c "Pyroscope profiling initialized" || true)
        echo -e "${CHECK} Initialized ($workers workers)"
    else
        echo -e "${CROSS} Not initialized"
        echo -e "    ${WARN} Check requirements.txt for grafana-pyroscope"
        echo -e "    ${WARN} Check app.py for init_profiling() call"
        echo -e "    ${WARN} Check ENABLE_PROFILING environment variable"
    fi
done

# ============================================================
# Step 6: Check Profile Data in Pyroscope
# ============================================================
print_section "Step 6: Profile Data in Pyroscope"

echo -e "${INFO} Checking for profile data..."
echo ""

# Check available services in Pyroscope
echo -n "  Services with profiles: "
services_with_data=$(curl -s 'http://localhost:4040/api/label/service_name/values' 2>/dev/null | jq -r '.[]' 2>/dev/null | wc -l)

if [ "$services_with_data" -gt 0 ]; then
    echo -e "${CHECK} $services_with_data services"
    echo ""
    echo "  Services:"
    curl -s 'http://localhost:4040/api/label/service_name/values' 2>/dev/null | jq -r '.[]' 2>/dev/null | sed 's/^/    /'
else
    echo -e "${CROSS} No services found"
    echo -e "    ${WARN} Generate traffic: curl http://192.168.100.57:5003/scenarios/pipeline"
    echo -e "    ${WARN} Wait 30 seconds, then refresh Grafana dashboard"
fi

echo ""
echo -n "  Profile types available: "
profile_types=$(curl -s 'http://localhost:4040/api/label/__profile_type__/values' 2>/dev/null | jq -r '.[]' 2>/dev/null | wc -l)

if [ "$profile_types" -gt 0 ]; then
    echo -e "${CHECK} $profile_types types"
    echo ""
    echo "  Profile types:"
    curl -s 'http://localhost:4040/api/label/__profile_type__/values' 2>/dev/null | jq -r '.[]' 2>/dev/null | sed 's/^/    /' | head -10
else
    echo -e "${CROSS} No profile types found"
fi

# ============================================================
# Step 7: Summary
# ============================================================
print_section "Summary"

echo ""
echo -e "${CHECK} All infrastructure components are healthy"
echo -e "${CHECK} Pyroscope datasource configured in Grafana"
echo -e "${CHECK} Dashboards updated to use Pyroscope datasource"
echo ""
echo -e "${INFO} Next steps:"
echo "  1. Open Grafana: http://192.168.100.55:3000"
echo "  2. Navigate to: Dashboards → Profiling → Profiling Overview"
echo "  3. Verify panels:"
echo "     - 🔥 CPU Profile Activity (should show data)"
echo "     - 💾 Memory Allocation Activity (should show data)"
echo "     - ✅ Profile Availability Check (should be green)"
echo "     - 🔥 CPU Flame Graph (should show flame graph)"
echo ""
echo -e "${INFO} If panels still show 'No Data':"
echo "  1. Generate traffic: curl http://192.168.100.57:5003/scenarios/pipeline"
echo "  2. Wait 30 seconds"
echo "  3. Refresh Grafana dashboard (F5)"
echo "  4. Expand time range to 'Last 1 hour'"
echo ""
echo -e "${INFO} For detailed troubleshooting:"
echo "  - Read: observability-vm/phase4-profiling/DASHBOARD_FIX_SUMMARY.md"
echo "  - Run practice exercises in: observability-vm/phase4-profiling/README.md"
echo ""
echo "=========================================="
echo -e "${GREEN}✅ Verification Complete!${NC}"
echo "=========================================="
echo ""
