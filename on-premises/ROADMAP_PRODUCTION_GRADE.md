# 🗺️ Production-Grade Reliability Lab Roadmap (1 Year)

**Owner:** Platform Engineering Team  
**Khởi tạo:** 2026-09-15  
**Phiên bản:** v2.0 — Integrated with EXPANSION_PLAN  
**Review Cycle:** Monthly

---

## 🎯 User Profile Summary

Dựa trên câu trả lời Q&A của bạn, roadmap được điều chỉnh như sau:

| Câu hỏi | Trả lời | Impact trên Roadmap |
|---------|---------|---------------------|
| Q1: Timeline | 1 năm+, production-grade | 4 Quý + Q5 (Phase 4-6) |
| Q2: Code confidence | Hiểu flow, chi tiết mông lung | Ưu tiên infra/observability (config, dashboards, alerts) trước Python code |
| Q3: Target context | Scale-up + Enterprise/Fintech | Mỗi phase có 2 tracks: Must-have (Scale-up) + Nice-to-have (Enterprise) |
| Q4: Chaos willingness | Sẵn sàng phá và sửa | Chaos exercises tích hợp từ Week 7, không đợi Phase 5 |

---

## 🔗 Mapping: Roadmap ↔ EXPANSION_PLAN

Đây là phần **quan trọng nhất** — hiểu rõ phần nào của roadmap kết hợp với phần nào của expansion plan.

| Roadmap Phase | EXPANSION_PLAN Phase | Mối quan hệ | Ghi chú |
|---------------|---------------------|-------------|---------|
| **Q1 Week 1-8** (Network, Logs, CB, Graceful Shutdown) | Phase 0: Infrastructure Hardening | 🟰 **Đồng bộ 1-1** | Đây chính là phần "Infrastructure Level" còn thiếu của Phase 0 |
| **Q1 Week 9-10** (DB Migration `orders` → `app_db`) | Phase 0 → Phase 1 transition | 🛡️ **Prerequisite** | Bắt buộc trước khi thêm Auth Service (EXPANSION_PLAN) |
| **Q1 Week 11-12** (TLS + Secrets) | Phase 1 prep | 🛡️ **Prerequisite** | Chuẩn bị infra trước khi deploy Auth Service |
| **Q2** (Auth Service) | Phase 1: Auth Service + TLS + Secrets | 🟰 **Đồng bộ 1-1** | Triển khai Auth + JWT + RBAC + Rate Limiting |
| **Q3** (Shipping + Saga) | Phase 2: Shipping + Worker + Backup | 🟰 **Đồng bộ 1-1** | Saga Orchestration + DLQ + Backup/Restore |
| **Q4** (Search + CQRS) | Phase 3: Search Service + Index Mgmt | 🟰 **Đồng bộ 1-1** | OpenSearch + eventual consistency |
| **Q5 Month 1-2** (Saga Tracing, SLO, Synthetic) | Phase 4: Advanced Observability | 🟰 **Đồng bộ 1-1** | Proactive reliability engineering |
| **Q5 Month 2-3** (Chaos Integration + DR) | Phase 5: Chaos + SLO + DR Drill | 🟰 **Đồng bộ 1-1** | Full-stack chaos, DR drill |
| **Q5 Month 3+** (k6 + Pact + Playwright) | Phase 6: Automated Testing | 🟰 **Đồng bộ 1-1** | CI reliability gates |

### 🎬 Key Insight

Roadmap này **KHÔNG phải là tài liệu song song** với EXPANSION_PLAN. Nó chính là **execution plan chi tiết** cho EXPANSION_PLAN, với:
- **Q1** = Phase 0 (Foundation — phần Infrastructure chưa được làm)
- **Q2-Q4** = Phase 1-3 (Application expansion)
- **Q5** = Phase 4-6 (Advanced reliability engineering)

**Dependency Graph (phải tuân thủ):**
```
Phase 0 (Q1) ──► Phase 1 (Q2) ──► Phase 2 (Q3) ──► Phase 3 (Q4) ──► Phase 4-6 (Q5)
     │                │                │                │
     │                │                │                │
     ▼                ▼                ▼                ▼
 Infra Harden    Auth/JWT/TLS    Saga/Shipping    Search/CQRS    Advanced Reliability
```

---

## 🏷️ Tag Legend

Mỗi task sẽ có 1-2 tags để bạn biết ngay tính chất công việc:

| Tag | Ý nghĩa | Khi nào thấy |
|-----|---------|--------------|
| 🔧 `[INFRA-ONLY]` | Chỉ cần chỉnh config/infra, **không cần đọc code Python** | docker-compose, Grafana, Prometheus, bash scripts |
| 🐍 `[CODE-CHANGE]` | Cần sửa code Python (nhưng tôi sẽ chỉ rõ "đổi dòng nào") | Khi cần áp dụng Circuit Breaker, add metrics |
| 📊 `[OBSERVABILITY]` | Grafana, Prometheus, Loki, Tempo work | Alerts, dashboards, recording rules |
| 🛡️ `[PREREQUISITE]` | **Phải hoàn thành** trước khi sang phase tiếp theo | Foundation work |
| 🏢 `[ENTERPRISE]` | Bắt buộc cho Fintech/Enterprise, optional cho Scale-up | mTLS, audit logs, secrets mgmt |
| ⚡ `[CHAOS-READY]` | Có chaos exercise đi kèm (vì Q4 = yes) | Mỗi phase đều có controlled failure injection |
| 📝 `[DOCUMENT]` | Chạy runbook, post-mortem, ADR | Documentation-first SRE |

---

## 📅 Timeline Overview

```
Q1 (Months 1-3)  : Phase 0 — Foundation
├── Week 1-2  : Network + Resource Limits  🔧 🛡️
├── Week 3-4  : Logs + Observability       🔧 📊
├── Week 5-6  : Circuit Breaker Universal  🐍 🛡️
├── Week 7-8  : First Chaos Exercises      ⚡
├── Week 9-10 : DB Migration → app_db      🔧 🛡️
└── Week 11-12: TLS + Secrets              🔧 🏢 🛡️

Q2 (Months 4-6)  : Phase 1 — Auth Service  🔗
├── Month 4   : auth_db + Auth Service     🐍 🛡️
├── Month 5   : JWT Middleware + RBAC      🐍 🛡️
└── Month 6   : Rate Limiting + Audit      🐍 📊 🏢

Q3 (Months 7-9)  : Phase 2 — Shipping/Saga 🔗
├── Month 7   : shipping_db + Service      🐍 🛡️
├── Month 8   : Saga Orchestrator          🐍 🛡️
└── Month 9   : DLQ + Backup/Restore       🔧 📊 🛡️

Q4 (Months 10-12): Phase 3 — Search/CQRS   🔗
├── Month 10  : OpenSearch + Service       🐍 🛡️
├── Month 11  : Event-driven indexing      🐍 📊
└── Month 12  : Index lag SLI + Backfill   📊 🛡️

Q5 (Months 13-15): Phase 4-6 — Advanced Reliability 🔗
├── Month 13  : Saga Tracing + SLO         📊 🔗
├── Month 14  : Synthetic Monitoring       🔧 📊
└── Month 15+ : k6 + Pact + Playwright     🐍 📊
```

---

# 🎯 Q1: INFRASTRUCTURE HARDENING (Phase 0)

## Week 1-2: Network Segmentation & Resource Limits

> 🔗 **Tương ứng:** EXPANSION_PLAN Phase 0 — Infrastructure Level items #1, #2  
> 🏷️ Tags: 🔧 `[INFRA-ONLY]` | 🛡️ `[PREREQUISITE]`

### Tại sao phải làm TRƯỚC KHI mở rộng services

Theo ARCHITECTURE.md section "Network Segmentation", hiện tại đang dùng **single Docker bridge network**. Nếu không tách network ngay bây giờ:
- Khi thêm Auth/Shipping/Search, tổng cộng **10 services trên 1 network** → 1 service bị compromise = **toàn bộ DB lộ** (vi phạm Zero Trust)
- `Blast Radius` (phạm vi ảnh hưởng) cực lớn, không thể isolate failures

### Tasks

- [ ] Tạo 4 Docker networks: `frontend`, `backend`, `data`, `observability`
- [ ] Assign mỗi service vào đúng network theo matrix bên dưới
- [ ] Set CPU/Memory limits dựa trên baseline metrics hiện tại (xem Capacity Planning trong ARCHITECTURE.md)
- [ ] Verify: Gateway KHÔNG thể ping PostgreSQL; chỉ Order/Payment/Workers access được DB

**Network Matrix:**

| Service | frontend | backend | data | observability |
|---------|:--------:|:-------:|:----:|:-------------:|
| web-ui | ✅ | | | |
| api-gateway | ✅ | ✅ | | |
| order-service | | ✅ | ✅ | |
| payment-service | | ✅ | ✅ | |
| notification-worker | | ✅ | ✅ | |
| inventory-worker | | ✅ | ✅ | |
| traffic-gen | | ✅ | | |
| postgres | | | ✅ | |
| redis | | | ✅ | |
| kafka | | | ✅ | |
| kafka-exporter | | | | ✅ |
| otel-collector (app side) | | | | ✅ |

### SRE Concepts học được

- `Network Segmentation` (Phân đoạn mạng) — Core principle của Zero Trust Architecture
- `Blast Radius Reduction` (Thu hẹp phạm vi ảnh hưởng) — Khi incident xảy ra, chỉ 1 phần hệ thống bị ảnh hưởng
- `Noisy Neighbor Problem` (Vấn đề hàng xóm ồn ào) — 1 service leak RAM không kéo sập cả VM
- `Defense in Depth` (Phòng thủ theo lớp) — Nhiều lớp bảo vệ, không phụ thuộc vào 1 lớp duy nhất

### Deliverables

- ✅ Updated `applications-vm/applications/docker-compose.yml` với 4 networks
- ✅ Resource limits cho mỗi service (theo bảng Capacity Planning trong ARCHITECTURE.md)
- ✅ Network connectivity matrix (service nào có thể connect service nào)
- ✅ Verification script (bash): check connectivity giữa services

### Exit Criteria

- ✅ `docker network ls` show 4 networks riêng biệt
- ✅ `docker exec web-ui ping postgres` → **FAIL** (vi phạm network policy = tốt!)
- ✅ `docker exec api-gateway ping order-service` → **OK** (cùng backend network)
- ✅ OOM Killer KHÔNG kill random containers khi 1 service leak memory (test bằng stress-ng)

### ⚡ Chaos Exercise (vì Q4 = yes)

```bash
# Memory leak simulation trong Order Service
docker exec order-service stress --vm 1 --vm-bytes 400M --vm-keep

# Verify: PostgreSQL và Web UI vẫn chạy bình thường
docker compose ps | grep -E "postgres|web-ui"

# Verify: OOM Killer kill Order Service, KHÔNG kill PostgreSQL
dmesg | grep -i "oom"
```

---

## Week 3-4: Observability Hardening & Log Management

> 🔗 **Tương ứng:** EXPANSION_PLAN Phase 0 — Infrastructure Level item #3  
> 🏷️ Tags: 🔧 `[INFRA-ONLY]` | 📊 `[OBSERVABILITY]`

### Tasks

- [ ] Cấu hình Docker log driver: `json-file` với `max-size: 10m`, `max-file: 5`
- [ ] Set up logrotate cho VM (`/var/lib/docker/containers/`)
- [ ] Verify Prometheus retention policy (15d storage, 2h memory)
- [ ] Tạo Grafana dashboard: Resource Usage, Network Traffic, Log Volume

### SRE Concepts học được

- `Disk Pressure Management` — Production killer #1 là disk full (sự cố phổ biến nhất)
- `Capacity Planning` — Dự báo resource usage để scale đúng lúc
- `Observability Pipeline Health` — Đảm bảo metrics/logs không bị drop trước khi đến backend

### Deliverables

- ✅ Updated `docker-compose.yml` với logging config cho TẤT CẢ services
- ✅ `/etc/logrotate.d/docker` trên VM
- ✅ Prometheus alerts: disk > 80%, high error rate, missing metrics
- ✅ Grafana dashboard "Infrastructure Health" (JSON trong `monitoring/grafana/dashboards/Infrastructure/`)

### Exit Criteria

- ✅ Docker logs tự động rotate khi đạt 10MB
- ✅ Alert fire khi disk usage > 80%
- ✅ Dashboard show resource usage của tất cả services

---

## Week 5-6: Circuit Breaker Universal & Graceful Shutdown Contract

> 🔗 **Tương ứng:** EXPANSION_PLAN Phase 0 — Infrastructure Level item #4 + Resilience Patterns  
> 🏷️ Tags: 🐍 `[CODE-CHANGE]` | 🛡️ `[PREREQUISITE]`  
> ⚠️ **Lưu ý cho Q2 (code mông lung):** Tôi sẽ chỉ rõ **chính xác dòng nào cần thêm** pybreaker. Bạn KHÔNG cần hiểu logic bên trong pybreaker, chỉ cần wrap function calls.

### Tasks

- [ ] Audit TẤT CẢ external calls (HTTP, DB, Kafka, Redis)
- [ ] Apply Circuit Breaker cho:
  - Gateway → Order Service (`🐍 [CODE-CHANGE]`)
  - Gateway → Payment Service (`🐍 [CODE-CHANGE]`)
  - Order Service → Payment Service (đã có pybreaker, chỉ verify)
  - Order Service → Kafka (`🐍 [CODE-CHANGE]`)
  - Order Service → Redis (`🐍 [CODE-CHANGE]`)
- [ ] Verify `stop_grace_period: 30s` match với shutdown timeout trong code

### Code Change Pattern (đơn giản, không cần hiểu sâu)

```python
# TRƯỚC (Gateway → Order Service trong api-gateway/app.py):
response = requests.post(ORDER_SERVICE_URL + "/process", json=body, timeout=30)

# SAU (wrap với pybreaker):
from shared.circuit_breakers import order_service_breaker

@order_service_breaker
def call_order_service(body):
    return requests.post(ORDER_SERVICE_URL + "/process", json=body, timeout=30)

response = call_order_service(body)
```

Tôi sẽ cung cấp **toàn bộ file `shared/circuit_breakers.py`** cho bạn copy vào codebase. Bạn chỉ cần:
1. Copy file vào `applications-vm/applications/shared/`
2. Thêm 1 dòng `from shared.circuit_breakers import ...` vào các file cần
3. Wrap function call với decorator

### SRE Concepts học được

- `Cascading Failure Prevention` (Ngăn ngừa lỗi dây chuyền) — Circuit Breaker phải có ở MỌI external call
- `Graceful Shutdown Contract` (Hợp đồng tắt máy nhã nhặn) — Container lifecycle management, tránh data loss
- `Failure Isolation` (Cô lập lỗi) — Bulkhead pattern, ngăn lỗi lan ra toàn hệ thống

### Exit Criteria

- ✅ Circuit Breaker open khi downstream failure > threshold (test bằng cách kill Payment Service)
- ✅ `docker stop <container>` hoàn thành trong 30s, không có SIGKILL (`docker inspect --format='{{.State.ExitCode}}'`)
- ✅ Không có in-flight requests bị drop khi shutdown (verify bằng log)

### ⚡ Chaos Exercise

```bash
# Kill Payment Service, verify Circuit Breaker opens ở Gateway
docker compose stop payment-service

# Theo dõi metric
curl -s http://localhost:9090/api/v1/query?query=circuit_breaker_state{state="open"}

# Gateway phải trả về fallback response sau 3 failures, KHÔNG timeout 30s
curl -X POST http://localhost:5000/order -H "Content-Type: application/json" -d '{"product_id":1,"quantity":1}'
```

---

## Week 7-8: First Chaos Engineering Exercise

> 🔗 **Tương ứng:** EXPANSION_PLAN Phase 5 (nhưng làm sớm vì Q4 = yes)  
> 🏷️ Tags: ⚡ `[CHAOS-READY]` | 📝 `[DOCUMENT]`

### 5 Scenarios (Controlled Blast Radius)

| # | Scenario | Tool | Blast Radius | SRE Lesson |
|---|----------|------|--------------|-----------|
| 1 | Network Latency (500ms + 10% packet loss Gateway↔Order) | `tc` + `pumba` | 2 services | `Latency Injection`, `Backpressure` |
| 2 | Service Crash (kill Order Service) | `docker kill` | 1 service | `Auto-restart`, `Graceful Shutdown` |
| 3 | DB Connection Saturation | Custom script | Data layer | `Connection Pool Sizing`, `PgBouncer need` |
| 4 | Kafka Partition Leader Failure | Kill Kafka broker | Event bus | `Leader Election`, `Consumer Lag` |
| 5 | Disk Pressure (fill to 90%) | `dd` command | VM-level | `Disk Pressure Alert`, `Capacity Planning` |

### Deliverables

- ✅ 5 Chaos scripts trong `on-premises/chaos/` (bash)
- ✅ 5 Post-Mortems theo template `post-mortems/00-TEMPLATE.md`
- ✅ Updated runbooks trong `INCIDENT_RUNBOOK.md`

### Exit Criteria

- ✅ Tất cả scenarios execute thành công, không có data loss
- ✅ 4/5 scenarios có automated detection (alerts, metric)
- ✅ All post-mortems documented

---

## Week 9-10: Database Migration `orders` → `app_db`

> 🔗 **Tương ứng:** EXPANSION_PLAN "Database Migration Plan" section  
> 🏷️ Tags: 🔧 `[INFRA-ONLY]` | 🛡️ `[PREREQUISITE]` — Bắt buộc trước Phase 1 (Auth Service)

### Tại sao phải làm TRƯỚC PHASE 1

Auth Service trong EXPANSION_PLAN Phase 1 cần connect tới `auth_db` trên cùng PostgreSQL instance. Nếu chưa tách `app_db`, Auth Service sẽ dùng chung `orders` DB → **vi phạm security best practice** (user credentials không được nằm chung với business data).

### Tasks

Toàn bộ đã được document chi tiết trong EXPANSION_PLAN.md section "Database Migration Plan (`orders` → `app_db`)". Bạn chỉ cần:

- [ ] Chạy `migration.sh` (copy từ EXPANSION_PLAN)
- [ ] Verify theo checklist trong EXPANSION_PLAN
- [ ] Giữ backup 24h trước khi cleanup

### SRE Concepts học được

- `Database Migration Procedure` — Production-grade migrations với pre-flight checklist, rollback plan, verification gates (kỹ năng **senior-level**)
- `Data Integrity Verification` — Checksums, row counts, foreign key checks
- `RTO/RPO` — Recovery Time Objective / Recovery Point Objective
- `Change Management` — Pre-flight checks, verification gates

### Exit Criteria

- ✅ Migration hoàn thành trong < 10 phút
- ✅ Zero data loss (verify bằng row count + checksum)
- ✅ Rollback script hoạt động trong < 2 phút (test TRƯỚC khi chạy migration thật)
- ✅ `DATABASE_URL` trong docker-compose.yml trỏ về `app_db`

### ⚡ Chaos Exercise

- Simulate failed migration: kill network giữa VM và PostgreSQL DURING `pg_restore` → verify rollback procedure hoạt động

---

## Week 11-12: TLS + Secrets Management

> 🔗 **Tương ứng:** EXPANSION_PLAN Phase 1 prep  
> 🏷️ Tags: 🔧 `[INFRA-ONLY]` | 🏢 `[ENTERPRISE]` | 🛡️ `[PREREQUISITE]`

### Tasks

- [ ] Generate self-signed CA + certificates (openssl)
- [ ] Configure nginx làm TLS termination
- [ ] HTTP → HTTPS redirect
- [ ] Chuyển secrets từ env vars trong `docker-compose.yml` sang Docker secrets / `.env` files
- [ ] `.env.*` files vào `.gitignore`

### SRE Concepts học được

- `Zero Trust Security` — mTLS giữa mọi services (Enterprise mandatory)
- `Secrets Lifecycle Management` — Rotation, revocation
- `TLS Termination` — Certificate management, nginx SSL config

### Scale-up vs Enterprise Track

| Task | Scale-up | Enterprise |
|------|----------|-----------|
| Self-signed CA | ✅ Required | ✅ Required |
| mTLS giữa services | Optional | ✅ Required |
| Secrets trong Docker secrets | ✅ Required | ✅ Required |
| HashiCorp Vault | Overkill | Nice-to-have |
| Certificate auto-rotation | Optional | ✅ Required |

### Exit Criteria

- ✅ HTTPS works, HTTP redirects
- ✅ Secrets KHÔNG plain text trong git
- ✅ `docker-compose.yml` KHÔNG còn inline passwords
- ✅ TLS 1.3, no weak ciphers (`openssl s_client -connect localhost:443`)

---

# 🎯 Q2: AUTH SERVICE + SECURITY (Phase 1 — EXPANSION_PLAN)

> 🔗 **Integrates với:** EXPANSION_PLAN Phase 1 "Auth Service + TLS + Secrets"  
> 🏷️ Tags: 🐍 `[CODE-CHANGE]` | 🛡️ `[PREREQUISITE]`

## Month 4: `auth_db` + Auth Service

### Tasks

- [ ] Tạo `auth_db` + `init-auth.sql` (copy schema từ EXPANSION_PLAN)
- [ ] Deploy Auth Service (5006) theo EXPANSION_PLAN
- [ ] Verify `/auth/register`, `/auth/login`, `/auth/verify` hoạt động
- [ ] Add auth service vào `backend` + `data` networks

### SRE Concepts

- `OAuth2/OIDC` — Industry standard authentication
- `JWT Validation` — Stateless authentication
- `Service-to-Service Auth` — Internal JWT với role `service`

### Exit Criteria

- ✅ Register → login → verify flow works
- ✅ `auth_db` isolated — Order Service KHÔNG thể query `users` table
- ✅ Health check `/health/ready` returns 200

## Month 5: JWT Middleware + RBAC ở Gateway

### Tasks

- [ ] Update API Gateway: thêm JWT middleware (local public key verification)
- [ ] Extract `user_id` từ token, inject vào downstream calls
- [ ] Update Order Service: add `user_id` vào orders table
- [ ] Update Web UI: login/register flow, localStorage

### Code Change Impact (cần AI Agents hỗ trợ)

| File | Thay đổi | Lines affected |
|------|---------|----------------|
| `api-gateway/app.py` | Thêm JWT middleware | +30 lines |
| `order-service/app.py` | Extract `user_id` từ header | +5 lines |
| `web-ui/app.js` | Login flow | +100 lines |

### Exit Criteria

- ✅ Unauthenticated request → 401
- ✅ Authenticated request → flow bình thường
- ✅ Expired token → 401, refresh → new token
- ✅ **Auth Service down → existing JWT vẫn valid** (local verification) ← Quan trọng!

## Month 6: Rate Limiting + Audit Logs

### Tasks

- [ ] Rate limiting ở Gateway (Redis-based sliding window)
- [ ] Audit logging cho authentication events (Loki)
- [ ] Grafana dashboard "Auth Overview"
- [ ] Alert: `AuthBruteForceDetected` (failed logins > 10/min từ 1 IP)

### Deliverables (from EXPANSION_PLAN Phase 1)

- ✅ RB-AUTH-01: Auth Service Down (new logins fail, existing sessions OK)
- ✅ RB-AUTH-02: Brute Force Detected
- ✅ RB-AUTH-03: JWT Key Rotation procedure
- ✅ RB-TLS-01: Certificate Expired / Renewal

### ⚡ Chaos Exercises

- Kill Auth Service → verify existing sessions still work (local JWT verification)
- Token validation failure → verify fallback behavior
- Session store (Redis) failure → verify graceful degradation

---

# 🎯 Q3: SHIPPING + SAGA ORCHESTRATION (Phase 2 — EXPANSION_PLAN)

> 🔗 **Integrates với:** EXPANSION_PLAN Phase 2 "Shipping Service + Worker + Backup"  
> 🏷️ Tags: 🐍 `[CODE-CHANGE]` | 🛡️ `[PREREQUISITE]`

## Month 7: `shipping_db` + Shipping Service

### Tasks

- [ ] Tạo `shipping_db` + `init-shipping.sql` (schema từ EXPANSION_PLAN)
- [ ] Deploy Shipping Service (5007) với REST API
- [ ] Add Circuit Breaker vào Shipping Worker → Shipping Service

### Exit Criteria

- ✅ Shipping Service CRUD hoạt động
- ✅ Circuit Breaker open khi Shipping Service down

## Month 8: Saga Orchestrator (Phức tạp nhất trong lab)

> ⚠️ **Lưu ý cho Q2:** Đây là phần code nặng nhất. Tôi sẽ cung cấp **toàn bộ class `SagaOrchestrator`** trong EXPANSION_PLAN. Bạn chỉ cần copy vào `shipping-worker/saga_orchestrator.py` và wire vào Kafka consumer loop. KHÔNG cần hiểu sâu logic bên trong.

### Tasks

- [ ] Copy `SagaOrchestrator` class từ EXPANSION_PLAN
- [ ] Wire vào Shipping Worker (Kafka consumer)
- [ ] Thêm Kafka topics: `order.shipped`, `order.shipping_failed`, `order.refunded`, `order.shipping.dlq`
- [ ] Add saga metrics vào OTel instrumentation

### 7 Invariants phải verify

Copy bảng 7 invariants từ EXPANSION_PLAN và test từng cái:

| # | Invariant | Test command |
|---|-----------|--------------|
| 1 | 1 order = 1 saga | Redeliver `order.payment_completed` 2 lần |
| 2 | No double refund | Kill worker during compensation |
| 3 | No double ship | Kill worker during shipping |
| 4 | No lost saga | Kill worker mid-step, wait 2 min, verify recovery |
| 5 | No zombie saga | Create saga with short timeout, verify → DEAD_LETTER |
| 6 | No race condition | Run 2 Shipping Worker instances |
| 7 | No half-done saga | Kill DB connection mid-transaction |

### Exit Criteria

- ✅ Tất cả 7 invariants pass
- ✅ Saga timeout → DLQ → manual review
- ✅ 2 Shipping Workers → Kafka rebalance, no duplicate

## Month 9: DLQ Handling + Backup/Restore Drill

### Tasks

- [ ] DLQ consumer + alerting
- [ ] Backup automation cho `app_db`, `auth_db`, `shipping_db` (cron job)
- [ ] Restore drill: dump → drop → restore → verify

### Deliverables

- ✅ RB-SAGA-01: Saga Stuck in PENDING
- ✅ RB-SAGA-02: DLQ Growing
- ✅ RB-SAGA-03: Shipping Service Down
- ✅ RB-BACKUP-01: Database Restore Procedure

### ⚡ Chaos Exercises

- Kill Shipping mid-saga → verify crash recovery
- Corrupt `saga_state` row → verify recovery job handles gracefully
- Full DB restore from backup → measure actual RTO

---

# 🎯 Q4: SEARCH + CQRS + EVENTUAL CONSISTENCY (Phase 3 — EXPANSION_PLAN)

> 🔗 **Integrates với:** EXPANSION_PLAN Phase 3 "Search Service + Index Management"  
> 🏷️ Tags: 🐍 `[CODE-CHANGE]` | 📊 `[OBSERVABILITY]`

## Month 10: OpenSearch + Search Service

### Tasks

- [ ] Add OpenSearch container vào docker-compose (resource limits: 3GB)
- [ ] Deploy Search Service (5009)
- [ ] Index products + orders

### Exit Criteria

- ✅ Search API trả về kết quả
- ✅ OpenSearch cluster health = green

## Month 11: Event-Driven Indexing

### Tasks

- [ ] Kafka consumer cho `order.created`, `order.updated`, `product.updated`
- [ ] Idempotent sync (order_id as document `_id`, upsert)
- [ ] Failure handling: `search.sync.dlq` cho failed indexing

### Exit Criteria

- ✅ Create order → search thấy sau ≤ 5s
- ✅ OpenSearch down → graceful error, core flow không ảnh hưởng

## Month 12: Index Lag SLI + Backfill

### Tasks

- [ ] Metric: `search_index_lag_seconds` (event timestamp vs `indexed_at`)
- [ ] Grafana dashboard "Search Health"
- [ ] Backfill procedure: POST `/search/reindex`
- [ ] Zero-downtime reindex: index aliasing (`orders_v1` → `orders_v2`)

### Deliverables

- ✅ RB-SEARCH-01: OpenSearch Cluster Red
- ✅ RB-SEARCH-02: Index Corruption → Reindex
- ✅ RB-SEARCH-03: Search Index Lag High

### ⚡ Chaos Exercises

- OpenSearch cluster degradation (high latency)
- Indexer failure → verify backfill
- Stale search results → verify fallback

---

# 🎯 Q5: ADVANCED RELIABILITY ENGINEERING (Phase 4-6 — EXPANSION_PLAN)

> 🔗 **Integrates với:** EXPANSION_PLAN Phase 4, 5, 6  
> 🏷️ Tags: 📊 `[OBSERVABILITY]` | ⚡ `[CHAOS-READY]` | 🐍 `[CODE-CHANGE]`

## Month 13: Saga Distributed Tracing + SLO/MWMBR (Phase 4)

### Tasks

- [ ] Inject `saga_id` vào OTel spans
- [ ] Propagate `saga_id` qua Kafka headers
- [ ] Grafana dashboard "Saga Monitor" (Node Graph plugin)
- [ ] MWMBR alerts cho Auth, Shipping, Search
- [ ] **Traffic Guards:** Áp dụng `traffic_source` label đã có trong codebase để tránh phantom alerts

### Deliverables (from EXPANSION_PLAN Phase 4)

- ✅ RB-SAGA-04: Saga High Failure Rate
- ✅ RB-SLO-NEW: SLO Violation cho Auth, Shipping, Search
- ✅ Saga Monitor dashboard với state machine flow

## Month 14: Synthetic Monitoring + Multi-ID Correlation (Phase 4C, 4D)

### Tasks

- [ ] Đóng gói Playwright E2E tests thành Docker container headless Chrome
- [ ] Chạy định kỳ 5 phút, push metrics về Prometheus Pushgateway
- [ ] Multi-ID log correlation (`user_id`, `session_id`, `order_id`, `saga_id`)
- [ ] Grafana Derived Fields → click `trace_id` → jump to Tempo
- [ ] Dashboard "Synthetic Journeys" + "User Activity"

### Deliverables

- ✅ RB-SYNTHETIC-01: Synthetic Journey Failing
- ✅ RB-CORRELATION-01: Debug User-Specific & Saga Issues

### ⚡ Chaos Exercise

- Stop Payment Service → verify **Synthetic Journey alert fires** dù server-side health checks vẫn pass (outside-in monitoring)

## Month 15+: k6 + Pact + Playwright (Phase 6)

### Tasks

- [ ] k6 load testing với Prometheus output → CI gate P99 < SLO
- [ ] Pact contract testing giữa 10 services
- [ ] Playwright synthetic journeys scheduled

### Deliverables

- ✅ CI gate auto-fail PR nếu P99 vượt SLO
- ✅ Pact broker catch breaking changes TRƯỚC KHI merge

---

# 📊 Success Metrics (Cumulative)

### Infrastructure Metrics (sau Q1)

- MTTR < 5 minutes cho Tier 1 incidents
- Zero data loss trong tất cả chaos exercises
- Resource utilization > 60% (không over-provisioned)

### Application Metrics (sau Q4)

- Availability > 99.9% (monthly)
- Error rate < 0.1%
- P95 latency < 500ms cho tất cả endpoints

### SRE Metrics (sau Q5)

- Toil < 30% of engineering time
- Incident detection automation > 90%
- 100% incidents có post-mortem trong 48h
- CI reliability gates chặn được 100% breaking changes

---

# 📚 Cross-References

| Bạn cần... | Đi đến... |
|-----------|-----------|
| Hiểu architecture hiện tại | `ARCHITECTURE.md` |
| Chi tiết expansion phases | `EXPANSION_PLAN.md` |
| Xử lý alert | `INCIDENT_RUNBOOK.md` |
| Thực hành incident | `INCIDENT_SIMULATION_GUIDE.md` |
| Break/test/recovery exercises | `BREAK_TEST_RECOVERY.md` |
| Post-mortem archive | `post-mortems/` |
| Hiểu môi trường | `on_premise-env.md` |

---

## 🔄 Revision History

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | 2026-09-15 | Initial roadmap |
| v2.0 | 2026-09-15 | Integrated với EXPANSION_PLAN; thêm mapping table, tag legend, Q5 (Phase 4-6); điều chỉnh cho Q2/Q3/Q4 |
| v2.1 | 2026-09-15 | ✅ Week 1-2 COMPLETED: Network Segmentation (3-tier), Resource Limits, Log Rotation, Graceful Shutdown Contract. See `WEEK1-2_CHANGES.md` and `DEPLOYMENT_GUIDE.md` |

---

**Last Updated:** 2026-09-15  
**Owner:** SRE Team (dungtt)  
**Next Review:** 2026-10-15
