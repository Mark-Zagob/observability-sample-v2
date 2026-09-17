#!/bin/bash
# ============================================================
# Week 1-2 Verification Script
# ============================================================
# Run this script after deploying to verify:
#   1. Network Segmentation
#   2. Resource Limits
#   3. Log Rotation
#   4. Graceful Shutdown
# ============================================================
# Usage:
#   chmod +x verify_week1-2.sh
#   ./verify_week1-2.sh
# ============================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; ((WARN++)); }
info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }

echo "============================================================"
echo "  Week 1-2 Verification Script"
echo "  Network Segmentation + Resource Limits + Log Rotation"
echo "============================================================"
echo ""

# ============================================================
# 1. NETWORK SEGMENTATION
# ============================================================
echo "============================================================"
echo "  1. NETWORK SEGMENTATION"
echo "============================================================"
echo ""

# Check networks exist
info "Checking Docker networks..."
NETWORKS=$(docker network ls --format '{{.Name}}')
for net in frontend backend data observability; do
  if echo "$NETWORKS" | grep -q "^${net}$"; then
    pass "Network '${net}' exists"
  else
    fail "Network '${net}' does NOT exist"
  fi
done

echo ""

# Check web-ui network membership
info "Checking web-ui network membership..."
WEB_UI_NETWORKS=$(docker inspect web-ui --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
if echo "$WEB_UI_NETWORKS" | grep -q "frontend" && echo "$WEB_UI_NETWORKS" | grep -q "backend"; then
  pass "web-ui is on frontend + backend networks"
else
  fail "web-ui is NOT on frontend + backend networks (got: $WEB_UI_NETWORKS)"
fi

# Check postgres network membership
info "Checking postgres network membership..."
POSTGRES_NETWORKS=$(docker inspect postgres --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
if echo "$POSTGRES_NETWORKS" | grep -q "data" && ! echo "$POSTGRES_NETWORKS" | grep -q "frontend"; then
  pass "postgres is on data network only"
else
  fail "postgres is NOT on data network only (got: $POSTGRES_NETWORKS)"
fi

# Check order-service network membership
info "Checking order-service network membership..."
ORDER_NETWORKS=$(docker inspect order-service --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
if echo "$ORDER_NETWORKS" | grep -q "backend" && echo "$ORDER_NETWORKS" | grep -q "data"; then
  pass "order-service is on backend + data networks"
else
  fail "order-service is NOT on backend + data networks (got: $ORDER_NETWORKS)"
fi

echo ""

# Network isolation tests
info "Testing network isolation..."

# web-ui should NOT be able to reach postgres
if docker exec web-ui ping -c 1 -W 2 postgres 2>/dev/null | grep -q "1 received"; then
  fail "SECURITY ISSUE: web-ui CAN reach postgres (should be isolated)"
else
  pass "web-ui CANNOT reach postgres (network isolation works)"
fi

# api-gateway should be able to reach order-service
if docker exec api-gateway ping -c 1 -W 2 order-service 2>/dev/null | grep -q "1 received"; then
  pass "api-gateway CAN reach order-service (backend network works)"
else
  fail "api-gateway CANNOT reach order-service (backend network broken)"
fi

# order-service should be able to reach postgres
if docker exec order-service ping -c 1 -W 2 postgres 2>/dev/null | grep -q "1 received"; then
  pass "order-service CAN reach postgres (data network works)"
else
  fail "order-service CANNOT reach postgres (data network broken)"
fi

echo ""

# ============================================================
# 2. RESOURCE LIMITS
# ============================================================
echo "============================================================"
echo "  2. RESOURCE LIMITS"
echo "============================================================"
echo ""

# Check resource limits for key services
check_resource_limit() {
  local service=$1
  local expected_mem=$2
  local expected_cpu=$3

  local mem
  mem=$(docker inspect "$service" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
  local cpu
  cpu=$(docker inspect "$service" --format '{{.HostConfig.NanoCpus}}' 2>/dev/null || echo "0")

  # Convert expected memory to bytes
  local expected_mem_bytes=0
  if [[ "$expected_mem" == *"G" ]]; then
    expected_mem_bytes=$(( ${expected_mem%G} * 1024 * 1024 * 1024 ))
  elif [[ "$expected_mem" == *"M" ]]; then
    expected_mem_bytes=$(( ${expected_mem%M} * 1024 * 1024 ))
  fi

  # Convert expected CPU to nanocpus (using awk instead of bc)
  local expected_cpu_nano
  expected_cpu_nano=$(echo "$expected_cpu" | awk '{printf "%d", $1 * 1000000000}')

  if [[ "$mem" == "$expected_mem_bytes" ]]; then
    pass "$service memory limit: $expected_mem"
  else
    fail "$service memory limit: expected $expected_mem ($expected_mem_bytes bytes), got $mem bytes"
  fi

  if [[ "$cpu" == "$expected_cpu_nano" ]]; then
    pass "$service CPU limit: $expected_cpu"
  else
    fail "$service CPU limit: expected $expected_cpu ($expected_cpu_nano nanocpus), got $cpu nanocpus"
  fi
}

info "Checking resource limits..."
check_resource_limit "api-gateway" "512M" "1.0"
check_resource_limit "order-service" "512M" "1.0"
check_resource_limit "payment-service" "256M" "0.5"
check_resource_limit "postgres" "2G" "2.0"
check_resource_limit "kafka" "4G" "2.0"
check_resource_limit "redis" "1G" "1.0"

echo ""

# Check resource usage
info "Current resource usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -20 || echo "(docker stats not available)"

echo ""

# ============================================================
# 3. LOG ROTATION
# ============================================================
echo "============================================================"
echo "  3. LOG ROTATION"
echo "============================================================"
echo ""

# Check logging driver
info "Checking logging configuration..."
for service in api-gateway order-service postgres kafka; do
  log_driver=$(docker inspect "$service" --format '{{.HostConfig.LogConfig.Type}}' 2>/dev/null || echo "unknown")
  log_opts=$(docker inspect "$service" --format '{{.HostConfig.LogConfig.Config}}' 2>/dev/null || echo "unknown")

  if [[ "$log_driver" == "json-file" ]]; then
    if echo "$log_opts" | grep -q "max-size:10m"; then
      pass "$service log rotation: json-file with max-size=10m"
    else
      warn "$service log driver is json-file but max-size may not be 10m (got: $log_opts)"
    fi
  else
    fail "$service log driver is NOT json-file (got: $log_driver)"
  fi
done

echo ""

# ============================================================
# 4. GRACEFUL SHUTDOWN
# ============================================================
echo "============================================================"
echo "  4. GRACEFUL SHUTDOWN CONTRACT"
echo "============================================================"
echo ""

# Check stop_grace_period
info "Checking stop_grace_period..."
for service in api-gateway order-service payment-service notification-worker inventory-worker; do
  grace=$(docker inspect "$service" --format '{{.Config.StopGracePeriod}}' 2>/dev/null || echo "0")
  # Docker returns in nanoseconds, 30s = 30000000000
  if [[ "$grace" == "30000000000" ]]; then
    pass "$service stop_grace_period: 30s"
  elif [[ "$grace" == "0" ]]; then
    warn "$service stop_grace_period: default (10s) — consider setting to 30s"
  else
    warn "$service stop_grace_period: got $grace ns (expected 30000000000 for 30s)"
  fi
done

# Check postgres and kafka have longer grace period
for service in postgres kafka; do
  grace=$(docker inspect "$service" --format '{{.Config.StopGracePeriod}}' 2>/dev/null || echo "0")
  if [[ "$grace" == "60000000000" ]]; then
    pass "$service stop_grace_period: 60s"
  else
    warn "$service stop_grace_period: got $grace ns (expected 60000000000 for 60s)"
  fi
done

echo ""

# Test graceful shutdown
info "Testing graceful shutdown (order-service)..."
info "Stopping order-service..."
START_TIME=$(date +%s)
docker compose stop order-service 2>/dev/null || docker stop order-service
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [[ $ELAPSED -ge 20 && $ELAPSED -le 40 ]]; then
  pass "order-service stopped in ${ELAPSED}s (expected ~25-30s)"
else
  warn "order-service stopped in ${ELAPSED}s (expected ~25-30s, may be too fast/slow)"
fi

# Check exit code (should be 0, not 137)
EXIT_CODE=$(docker inspect order-service --format '{{.State.ExitCode}}' 2>/dev/null || echo "-1")
if [[ "$EXIT_CODE" == "0" ]]; then
  pass "order-service exit code: 0 (graceful shutdown)"
elif [[ "$EXIT_CODE" == "137" ]]; then
  fail "order-service exit code: 137 (SIGKILL — graceful shutdown failed)"
else
  warn "order-service exit code: $EXIT_CODE"
fi

# Restart the service
info "Restarting order-service..."
docker compose start order-service 2>/dev/null || docker start order-service
sleep 5

echo ""

# ============================================================
# 5. SERVICE HEALTH
# ============================================================
echo "============================================================"
echo "  5. SERVICE HEALTH CHECKS"
echo "============================================================"
echo ""

# Check health endpoints
info "Checking application health endpoints..."
for port in 5000 5001 5002 5004 5005; do
  status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health/ready" 2>/dev/null || echo "000")
  if [[ "$status" == "200" ]]; then
    pass "Port $port health check: 200 OK"
  else
    fail "Port $port health check: $status (expected 200)"
  fi
done

echo ""

# ============================================================
# SUMMARY
# ============================================================
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"
echo ""
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}🎉 All critical checks passed! Week 1-2 hardening is complete.${NC}"
  echo ""
  echo "Next steps:"
  echo "  - Week 3-4: Observability Hardening (Prometheus alerts, Grafana dashboards)"
  echo "  - Week 5-6: Circuit Breaker Universal"
  echo "  - Week 7-8: First Chaos Engineering Exercises"
else
  echo -e "${RED}⚠️  Some checks failed. Please review the output above and fix issues.${NC}"
  echo ""
  echo "Common fixes:"
  echo "  - Network issues: Recreate containers with 'docker compose up -d --force-recreate'"
  echo "  - Resource limits: Verify docker-compose.yml has 'deploy.resources.limits'"
  echo "  - Log rotation: Verify 'logging' section in docker-compose.yml"
  echo "  - Graceful shutdown: Verify 'stop_grace_period' in docker-compose.yml"
fi

echo ""
echo "============================================================"
exit $FAIL
