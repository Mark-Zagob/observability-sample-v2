# Repository Context Map

> **Mục đích:** File này là "bản đồ điều hướng" cho AI. Upload file này + AI-introduce.md + ARCHITECTURE.md ở ĐẦU MỖI SESSION để AI hiểu tổng quan repo.
>
> **Cập nhật:** 2026-05-28 | **Version:** 2.0

---

## 🧭 ROUTING TABLE — Đọc gì khi user hỏi gì?

| Nếu user hỏi về... | Bắt đầu từ | Drill-down nếu cần |
|--------------------|-----------|---------------------|
| Kiến trúc tổng thể, data flow, design patterns | ARCHITECTURE.md | — |
| Service mới, code convention, Kafka, error handling | **APP-INDEX.md** | Source code tương ứng |
| Prometheus, Loki, Tempo, OTel Collector, dashboards, alert rules | **OBSERVABILITY-INDEX.md** | Config files tương ứng |
| Docker Compose, backup, secrets, CI/CD, security | **OPS-INDEX.md** | docker-compose.yml, scripts/ |
| Interview questions, incident simulation, BTR exercises, post-mortem | **LEARNING-INDEX.md** | Các guide files |
| Xử lý alert cụ thể (RB-01 → RB-24) | INCIDENT_RUNBOOK.md | — |
| Kế hoạch mở rộng 6→10 services (Saga, CQRS, Circuit Breaker) | EXPANSION_PLAN.md | — |

**Quick PromQL / LogQL query:** chỉ cần file này.
**Debug alert / dashboard:** file này + OBSERVABILITY-INDEX.md.
**Code review / add service:** file này + APP-INDEX.md.
**Full architecture review:** file này + ARCHITECTURE.md + EXPANSION_PLAN.md.

---

## 📊 REPOSITORY STATS

| Metric | Count |
|--------|-------|
| Application services | 6 (api-gateway, order, payment, notification-worker, inventory-worker, traffic-gen) |
| Infrastructure services | 9 (postgres, redis, kafka, kafka-exporter, kafka-ui, web-ui, minio, alloy, blackbox) |
| Observability tools | 6 (Prometheus, Grafana, Loki, Tempo, OTel Collector, Alertmanager) |
| Design patterns áp dụng | 11 (Event-Driven, Idempotent, Cache-Aside, Pessimistic Lock, BFF, Multi-Stage Build, Health Check, Structured Logging, RFC 7807, Graceful Shutdown, Distributed Trace Propagation) |
| Kafka topics | 1 (order.events với 4 event types) |
| Grafana dashboards | 15 (Alerting, Application×6, Infrastructure×3, Logging×2, Tracing×2) |
| Alert rules | 24 (infra, SLO burn rate, Kafka, application, health check) |
| Incident simulation experiments | 12 |
| Break/Test/Recovery exercises | 28 (across 7 components) |
| Interview questions | 76 (45 junior-mid + 31 senior) |
| VMs | 2 (Applications VM 192.168.100.57 + Observability VM 192.168.100.55) |

---

## 🎯 PROJECT OVERVIEW

**Observability Lab** — E-commerce microservices platform dùng để học và thực hành SRE/DevOps ở mức production-grade.

**Triết lý:** KHÔNG phải toy project. Docker Compose được dùng như **production orchestrator** — mọi aspect (TLS, secrets, network segmentation, backup, CI, graceful shutdown) đều production-grade. Chỉ khác Kubernetes ở deployment tooling, không khác ở operational practices.

**Mục tiêu học tập:**
- Thực hành observability (Metrics + Logs + Traces) với team size khác nhau
- Demo production patterns: distributed tracing, SLO/SLI, incident management
- Luyện incident response với runbook + simulation + post-mortem
- Nghiên cứu event-driven architecture với Kafka

---

## 🛠️ TECH STACK

| Layer | Technology |
|-------|-----------|
| **Application** | Python 3.12 (Flask), Gunicorn (gthread), Node.js (nginx SPA) |
| **Instrumentation** | OpenTelemetry SDK 1.33 (auto + manual) |
| **Message Broker** | Kafka 3.7 (KRaft mode, no ZooKeeper) |
| **Database** | PostgreSQL 16, Redis 7 |
| **Observability** | Prometheus 3.10, Grafana 12.3, Loki 3.3, Tempo 2.7, OTel Collector 0.120, Alloy 1.13 |
| **Alerting** | Alertmanager 0.28 → Telegram + Webhook |
| **Storage** | MinIO (S3-compatible) cho Loki chunks + Tempo blocks |
| **Deployment** | Docker Compose (2 VMs), multi-stage builds, security hardened |

---

## 🏗️ ARCHITECTURE (High-Level)

```
Web UI :8580 → API Gateway :5000 → Order Service :5001 → Payment Service :5002
                                        ↓ (Kafka :9092)
                          [Notification Worker :5004, Inventory Worker :5005]
                                        ↓
                                   PostgreSQL :5432

Telemetry: All Services → OTel Collector :4317 → [Prometheus, Loki, Tempo]
                                                        ↓
                                                  Grafana :3000

Blackbox Exporter :9115 → probe /health/live (every 15s)
```

**Data flows:**

- **Sync (HTTP):** User → Web UI → API Gateway → Order → Payment
- **Async (Kafka):** Order → `order.events` → [Notification Worker, Inventory Worker]
- **Telemetry:** Apps → OTLP gRPC → OTel Collector → fan-out to backends

Chi tiết: xem `ARCHITECTURE.md`

---

## 📦 SERVICES SUMMARY

| Port | Service | Role | DB | Key Patterns |
|------|---------|------|----|---------------|
| 8580 | web-ui | Nginx SPA + reverse proxy | - | DNS resolver 10s |
| 5000 | api-gateway | BFF, routes requests | - | RFC 7807, circuit breaker (planned) |
| 5001 | order-service | Create orders, publish events | app_db + Redis | Cache-aside, Kafka producer |
| 5002 | payment-service | Simulated payment | app_db | Random latency/errors |
| 5003 | traffic-gen | Load testing scenarios | - | Scenario templates |
| 5004 | notification-worker | Kafka consumer → notifications | app_db | Idempotent, graceful shutdown |
| 5005 | inventory-worker | Kafka consumer → stock mgmt | app_db | Pessimistic lock, auto-restock |

**Kafka topic:** `order.events` với event types:

- `order.created`, `order.payment_completed`, `order.payment_failed`, `stock.depleted`

---

## 🔭 OBSERVABILITY STACK

### Pipeline

```
Services → OTLP gRPC → OTel Collector → Prometheus (metrics)
                                       → Tempo (traces, tail-sampled)
                                       → Loki (logs, via Alloy)

Blackbox → HTTP probes → Prometheus (availability 24/7)
```

### Key Configurations

- **Scrape interval:** 15s (chuẩn hóa toàn hệ thống)
- **Tail sampling:** 100% errors, 100% >500ms, 10% normal
- **Spanmetrics connector:** auto RED metrics từ traces
- **Retention:** 7 days (Loki/Tempo), 15 days (Prometheus)

### SLOs
| Service | SLI | Target |
|---------|-----|--------|
| API Gateway | Availability (non-5xx) | 99.5% |
| API Gateway | Latency P95 < 500ms | 95% |
| Payment | Success rate | 99.0% |

### Alerting (MWMBR pattern)
- **Fast burn (critical):** 14.4x trong 5m+1h windows → page
- **Slow burn (warning):** 3x trong 30m+6h windows → ticket
- **Traffic guards:** `rate(total[5m]) > 0.1` để tránh phantom alerts

Chi tiết: xem `OBSERVABILITY-INDEX.md`

---

## 🎨 KEY CONVENTIONS (Quick Reference)

| Convention | Pattern | Example |
|------------|---------|---------|
| **Metric name** | `{namespace}_{subsystem}_{name}_{unit}` snake_case | `orders_created_total` |
| **Service name** | kebab-case | `order-service`, `inventory-worker` |
| **Kafka topic** | dot.notation | `order.events`, `order.shipping.dlq` |
| **Span name** | `<domain>.<operation>` | `catalog.fetch`, `kafka.produce` |
| **Log fields** | snake_case | `order_id`, `user_id`, `payment_txn_id` |
| **Error response** | RFC 7807 + `trace_id` + `error_code` | `ERR_DOMAIN_PROBLEM` |
| **Health endpoints** | `/health/live` (process) + `/health/ready` (with deps) | — |
| **Alert severity** | critical (page 1-5m) / warning (ticket 5-30m) / info | — |
| **Recording rule** | `{level}:{metric}:{operation}` | `service:request_rate:5m` |
| **Alert name** | PascalCase `{Service}{Problem}` | `APIGatewayFastBurn` |

Chi tiết: xem `APP-INDEX.md`, `OBSERVABILITY-INDEX.md`, `OPS-INDEX.md`

---

## ⛔ TOP ANTI-PATTERNS (Cần tránh)

1. ❌ High-cardinality labels trong metrics (`user_id`, `request_id`, `http.url`)
2. ❌ Check DB/Cache trong liveness probe (gây CrashLoopBackOff)
3. ❌ Log PII, dùng `print()`, thiếu `exc_info=True` khi log exception
4. ❌ SLO alerts KHÔNG có traffic guard (phantom alerts khi không có traffic)
5. ❌ Kafka consumer không handle SIGTERM (duplicate processing)
6. ❌ Hardcode secrets trong docker-compose.yml
7. ❌ Không set resource limits (OOM killer)
8. ❌ Dùng shared database cho tất cả services khi scale > 10 services

Chi tiết anti-patterns per domain: xem các INDEX files tương ứng.

---

## 🔗 CROSS-REFERENCES

### Tier 1 Files (Always-on, upload mỗi chat)
- `AI-introduce.md` — Giới thiệu repository và mục tiêu
- `ARCHITECTURE.md` — Kiến trúc chi tiết, data flows, design patterns, ADRs
- **`CONTEXT.md`** (file này) — Bản đồ điều hướng

### Tier 2 Files (Domain Index, upload theo chủ đề)
- **`APP-INDEX.md`** — Application conventions (coding, Kafka, errors, health, OTel)
- **`OBSERVABILITY-INDEX.md`** — Observability conventions (Prometheus, Loki, Tempo, dashboards, alerts)
- **`OPS-INDEX.md`** — Operations conventions (Docker, backup, secrets, CI/CD, security)
- **`LEARNING-INDEX.md`** — Learning resources (interview, incidents, BTR, post-mortem)

### Tier 3 Files (Deep-dive, upload on-demand)
- `INCIDENT_RUNBOOK.md` — Runbook xử lý 24 loại alert
- `INCIDENT_SIMULATION_GUIDE.md` — 12 experiments giả lập incident
- `BREAK_TEST_RECOVERY.md` — 28 exercises break/test/recovery
- `EXPANSION_PLAN.md` — Kế hoạch mở rộng 6→10 services
- Source code files cụ thể (khi cần code review)

---

## 📚 USAGE WORKFLOW

### Khi bắt đầu session mới:
1. Upload: `AI-introduce.md` + `ARCHITECTURE.md` + `CONTEXT.md` (file này)
2. AI đã có đủ context tổng quan (~5-6k tokens)

### Khi cần drill-down:
- **Code task:** + `APP-INDEX.md`
- **Observability task:** + `OBSERVABILITY-INDEX.md`
- **Infrastructure task:** + `OPS-INDEX.md`
- **Learning/interview:** + `LEARNING-INDEX.md`

### Khi cần chi tiết cụ thể:
- + source code files / config files / runbook tương ứng