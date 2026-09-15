# 🛡️ Week 1-2: Network Segmentation & Resource Limits — Implementation Summary

**Date:** 2026-09-15  
**Owner:** SRE Team (dungtt)  
**Status:** ✅ COMPLETED  
**Related:** `ROADMAP_PRODUCTION_GRADE.md` Week 1-2, `ARCHITECTURE.md` Section "Network Segmentation" & "Capacity Planning"

---

## 📋 Tổng quan thay đổi

### 1. Network Segmentation — 3-Tier Architecture

**TRƯỚC (single network):**
```
Tất cả 12 services chạy trên 1 Docker bridge network "observability"
→ web-ui có thể ping thẳng PostgreSQL (vi phạm Zero Trust)
→ 1 service bị compromise = toàn bộ DB lộ (Blast Radius cực lớn)
```

**SAU (3-tier segmentation):**
```
┌─────────────────────────────────────────────────────────────┐
│                    FRONTEND Network                          │
│  web-ui ←→ api-gateway                                      │
│  (External-facing, receives traffic from outside)            │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    BACKEND Network                           │
│  web-ui, api-gateway ←→ order-service, payment-service,     │
│  notification-worker, inventory-worker, traffic-gen         │
│  (Internal business logic)                                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                     DATA Network                             │
│  order-service, payment-service, workers ←→ postgres,       │
│  redis, kafka, kafka-exporter, kafka-ui                     │
│  (Data stores — restricted access)                           │
└─────────────────────────────────────────────────────────────┘
```

### Network Connectivity Matrix

| Service | frontend | backend | data | Có thể reach |
|---------|:--------:|:-------:|:----:|-------------|
| **web-ui** | ✅ | ✅ | ❌ | api-gateway, traffic-gen, workers (reverse proxy) |
| **api-gateway** | ✅ | ✅ | ❌ | web-ui, order-service, payment-service, traffic-gen |
| **order-service** | ❌ | ✅ | ✅ | api-gateway, payment-service, postgres, redis, kafka |
| **payment-service** | ❌ | ✅ | ✅ | order-service, redis |
| **notification-worker** | ❌ | ✅ | ✅ | postgres, kafka |
| **inventory-worker** | ❌ | ✅ | ✅ | postgres, kafka |
| **traffic-gen** | ❌ | ✅ | ❌ | api-gateway |
| **postgres** | ❌ | ❌ | ✅ | (chỉ nhận connections) |
| **redis** | ❌ | ❌ | ✅ | (chỉ nhận connections) |
| **kafka** | ❌ | ❌ | ✅ | (chỉ nhận connections) |
| **kafka-exporter** | ❌ | ❌ | ✅ | kafka |
| **kafka-ui** | ❌ | ❌ | ✅ | kafka |

### Security Benefits (Zero Trust)

| Attack Scenario | Before | After |
|----------------|--------|-------|
| web-ui bị compromise | Attacker scan toàn bộ network, tìm PostgreSQL | Attacker chỉ thấy frontend + backend, KHÔNG thấy PostgreSQL |
| api-gateway bị compromise | Attacker connect thẳng tới Redis/Kafka | Attacker KHÔNG thể access data layer |
| 1 worker bị compromise | Attacker lateral move sang tất cả services | Attacker chỉ thấy backend + data, không thể ra frontend |

---

### 2. Resource Limits — Noisy Neighbor Prevention

**Vấn đề:** Không có CPU/Memory limits → 1 service leak RAM có thể kéo sập cả VM (OOM Killer chọn random container để kill, có thể là PostgreSQL!)

**Giải pháp:** Set limits theo `ARCHITECTURE.md` Capacity Planning section.

| Service | CPU Limit | Memory Limit | CPU Reservation | Memory Reservation |
|---------|-----------|--------------|-----------------|---------------------|
| **postgres** | 2.0 | 2G | 0.5 | 512M |
| **kafka** | 2.0 | 4G | 0.5 | 1G |
| **redis** | 1.0 | 1G | 0.25 | 128M |
| **api-gateway** | 1.0 | 512M | 0.25 | 128M |
| **order-service** | 1.0 | 512M | 0.25 | 128M |
| **payment-service** | 0.5 | 256M | 0.1 | 64M |
| **notification-worker** | 0.5 | 256M | 0.1 | 64M |
| **inventory-worker** | 0.5 | 256M | 0.1 | 64M |
| **traffic-gen** | 0.5 | 256M | 0.1 | 64M |
| **kafka-ui** | 0.5 | 512M | 0.1 | 128M |
| **kafka-exporter** | 0.25 | 128M | 0.05 | 32M |
| **web-ui** | 0.25 | 128M | 0.05 | 32M |

**Observability VM Resources:**

| Service | CPU Limit | Memory Limit |
|---------|-----------|--------------|
| **prometheus** | 1.0 | 2G |
| **loki** | 1.0 | 2G |
| **tempo** | 1.0 | 2G |
| **grafana** | 1.0 | 1G |
| **otel-collector** | 1.0 | 1G |
| **minio** | 1.0 | 1G |
| **alertmanager** | 0.5 | 256M |
| **alloy** (both VMs) | 0.5 | 512M |
| **cadvisor** (both VMs) | 0.5 | 256M |
| **node-exporter** (both VMs) | 0.25 | 128M |
| **blackbox-exporter** | 0.25 | 128M |
| **webhook-receiver** | 0.25 | 128M |

**SRE Concepts học được:**
- `Noisy Neighbor Problem` — 1 service hog resources, ảnh hưởng services khác
- `Bulkhead Pattern` — Vách ngăn chống chìm tàu, mỗi service có resource riêng
- `Capacity Planning` — Dự báo resource usage để scale đúng lúc
- `Resource Reservations` — Đảm bảo minimum resources cho mỗi service

---

### 3. Log Rotation — Disk Pressure Management

**Vấn đề:** Docker logs grow vô hạn → disk đầy → toàn bộ VM down (production killer #1)

**Giải pháp:** Apply `json-file` driver với `max-size: 10m`, `max-file: 5` cho TẤT CẢ services.

```yaml
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"    # Mỗi file log tối đa 10MB
    max-file: "5"      # Giữ tối đa 5 files → tổng 50MB per container
```

**SRE Concepts học được:**
- `Disk Pressure Management` — Production killer #1 là disk full
- `Log Lifecycle Management` — Log không nên tồn tại vĩnh viễn trên host

---

### 4. Graceful Shutdown Contract

**Vấn đề:** Docker Compose mặc định `stop_grace_period: 10s`, nhưng code có `graceful_timeout: 25s` → SIGKILL cắt ngang giữa chừng → Kafka offset commit fail → duplicate processing.

**Giải pháp:** Set `stop_grace_period: 30s` cho tất cả application services, `60s` cho PostgreSQL/Kafka.

| Service Type | stop_grace_period | Lý do |
|-------------|-------------------|-------|
| Application services | 30s | Match gunicorn graceful_timeout (25s) + 5s buffer |
| PostgreSQL | 60s | Cần flush WAL, close connections gracefully |
| Kafka | 60s | Cần partition leader election, flush logs |
| Infrastructure (redis, exporters) | Default (10s) | Stateless, fast shutdown |

**SRE Concepts học được:**
- `Graceful Shutdown Contract` — Orchestrator và application phải agree on timeout
- `In-flight Request Handling` — Không drop requests khi shutdown
- `Offset Commit Safety` — Kafka consumer phải commit offset trước khi exit

---

## 📁 Files đã thay đổi

### Applications VM (192.168.100.57)

| File | Thay đổi |
|------|---------|
| `applications-vm/applications/docker-compose.yml` | ✅ 3 networks (frontend/backend/data), resource limits, log rotation, stop_grace_period |
| `applications-vm/agents/docker-compose.yml` | ✅ Resource limits, log rotation |

### Observability VM (192.168.100.55)

| File | Thay đổi |
|------|---------|
| `observability-vm/phase1-metrics/docker-compose.yml` | ✅ Resource limits, log rotation |
| `observability-vm/phase2-logging/docker-compose.yml` | ✅ Resource limits, log rotation |
| `observability-vm/phase3-tracing/docker-compose.yml` | ✅ Resource limits, log rotation |
| `observability-vm/storage/docker-compose.yml` | ✅ Resource limits, log rotation |

---

## ✅ Verification Checklist

### 1. Network Segmentation Verification

```bash
# ✅ web-ui KHÔNG thể ping postgres (KHÁC network)
docker exec web-ui ping -c 1 postgres
# Expected: "ping: bad address 'postgres'" hoặc "Network is unreachable"

# ✅ api-gateway có thể ping order-service (CÙNG backend network)
docker exec api-gateway ping -c 1 order-service
# Expected: 1 packet transmitted, 1 received

# ✅ order-service có thể ping postgres (CÙNG data network)
docker exec order-service ping -c 1 postgres
# Expected: 1 packet transmitted, 1 received

# ❌ web-ui KHÔNG thể ping redis (KHÁC network)
docker exec web-ui ping -c 1 redis
# Expected: "ping: bad address 'redis'" hoặc timeout

# Verify networks
docker network ls
# Expected: frontend, backend, data, observability (4 networks)

# Verify network membership
docker inspect web-ui --format '{{json .NetworkSettings.Networks}}' | jq
# Expected: {"frontend": {...}, "backend": {...}}

docker inspect postgres --format '{{json .NetworkSettings.Networks}}' | jq
# Expected: {"data": {...}}
```

### 2. Resource Limits Verification

```bash
# Verify resource limits
docker inspect api-gateway --format '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}'
# Expected: 536870912 1000000000 (512MB, 1.0 CPU)

# Check resource usage real-time
docker stats --no-stream
# Verify: no container exceeds its limit

# Simulate memory leak (Chaos Exercise)
docker exec order-service sh -c "apt-get update && apt-get install -y stress && stress --vm 1 --vm-bytes 400M --vm-keep"
# Expected: OOM Killer kills order-service, PostgreSQL remains healthy
# Verify: docker compose ps | grep postgres → Status: healthy
```

### 3. Log Rotation Verification

```bash
# Check logging driver
docker inspect api-gateway --format '{{.HostConfig.LogConfig.Type}}'
# Expected: json-file

docker inspect api-gateway --format '{{.HostConfig.LogConfig.Config}}'
# Expected: map[max-file:5 max-size:10m]

# Simulate log growth
docker exec api-gateway sh -c "for i in $(seq 1 100000); do echo 'test log line $i'; done"
# Verify: log files rotate at 10MB
ls -lh /var/lib/docker/containers/<container-id>/*.log
# Expected: multiple files, each ~10MB
```

### 4. Graceful Shutdown Verification

```bash
# Stop a service and measure time
time docker compose stop order-service
# Expected: ~25-30s (not 10s default, not instant)

# Check exit code (should be 0, not 137 = SIGKILL)
docker inspect order-service --format '{{.State.ExitCode}}'
# Expected: 0

# Check logs for graceful shutdown messages
docker compose logs --tail=20 order-service | grep -i "shutdown\|graceful\|SIGTERM"
# Expected: "🛑 Received SIGINT/SIGTERM, finishing current request gracefully..."
```

---

## ⚡ Chaos Exercises (Week 1-2)

### Exercise 1: Noisy Neighbor (Memory Leak)

**Mục tiêu:** Verify resource limits protect PostgreSQL khỏi OOM Killer.

```bash
# 1. Verify PostgreSQL healthy
docker exec postgres pg_isready -U app -d orders
# Expected: accepting connections

# 2. Inject memory leak in order-service
docker exec order-service sh -c "apt-get update && apt-get install -y stress && stress --vm 1 --vm-bytes 400M --vm-keep &"

# 3. Monitor
docker stats --no-stream | grep -E "order-service|postgres"
# Expected: order-service memory approaches 512M limit, postgres stays stable

# 4. Verify OOM Killer targets order-service, NOT postgres
dmesg | grep -i "oom\|killed process"
# Expected: order-service killed, postgres untouched

# 5. Verify auto-restart
docker compose ps | grep order-service
# Expected: restarting or running (after auto-restart)
```

### Exercise 2: Network Isolation

**Mục tiêu:** Verify web-ui cannot access data layer.

```bash
# 1. From web-ui, try to connect to postgres
docker exec web-ui sh -c "wget -q -O- --timeout=3 http://postgres:5432 || echo 'CONNECTION BLOCKED'"
# Expected: "CONNECTION BLOCKED" or "bad address"

# 2. From order-service, connect to postgres (should work)
docker exec order-service sh -c "python -c \"import psycopg2; conn = psycopg2.connect('postgresql://app:***@postgres:5432/orders'); print('CONNECTED'); conn.close()\""
# Expected: "CONNECTED"

# 3. Verify Grafana still receives metrics (observability unaffected)
curl -s http://192.168.100.55:9090/api/v1/query?query=up | jq .
# Expected: all targets up
```

---

## 🚀 Deployment Guide (Linux VM)

Xem chi tiết trong `DEPLOYMENT_GUIDE.md`.

---

## 📚 SRE Concepts Summary

| Concept | Definition | Applied In |
|---------|-----------|------------|
| `Network Segmentation` | Chia network thành zones riêng biệt theo trust level | 3-tier: frontend, backend, data |
| `Blast Radius Reduction` | Thu hẹp phạm vi ảnh hưởng khi incident xảy ra | web-ui compromise không lộ DB |
| `Noisy Neighbor Problem` | 1 service hog resources, ảnh hưởng services khác | Resource limits per container |
| `Bulkhead Pattern` | Vách ngăn chống chìm tàu, isolate failures | Each service has own resource pool |
| `Disk Pressure Management` | Prevent disk full incidents | Log rotation: 10MB × 5 files |
| `Graceful Shutdown Contract` | Agreement between orchestrator and app on shutdown timeout | stop_grace_period: 30s |
| `Zero Trust Architecture` | Never trust, always verify | No implicit network trust |
| `Defense in Depth` | Multiple security layers | Network + resource + security hardening |

---

## 🔄 Next Steps

- **Week 3-4:** Observability Hardening & Log Management (Prometheus alerts, Grafana dashboards)
- **Week 5-6:** Circuit Breaker Universal (apply pybreaker to all external calls)
- **Week 7-8:** First Chaos Engineering Exercises (5 controlled scenarios)

---

**Document Version:** 1.0  
**Last Updated:** 2026-09-15  
**Next Review:** After Week 3-4 completion
