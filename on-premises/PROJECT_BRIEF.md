# PROJECT_BRIEF.md

> **Mục đích:** Context siêu ngắn (~1k tokens) cho AI Web Chat khi làm task đơn giản.
> **Khi cần chi tiết:** Paste thêm `CONVENTIONS.md` (coding rules) hoặc `ARCHITECTURE.md` (kiến trúc đầy đủ).
> **Cập nhật:** 2026-05-27

---

## 🎯 Project
**Observability Lab** — E-commerce microservices platform dùng để học và thực hành SRE/DevOps ở mức production-grade.

## 🛠️ Tech Stack
- **App:** Python 3.11, Flask, psycopg2, redis-py, confluent-kafka
- **Infra:** Docker Compose, 2 VMs (App VM 192.168.100.57 + Observability VM 192.168.100.55)
- **Data:** PostgreSQL 16, Redis 7, Kafka 3.7 (KRaft mode)
- **Observability:** Prometheus, Grafana, Loki, Tempo, OTel Collector, Alloy, Alertmanager
- **Alerting:** Alertmanager → Telegram + Webhook

## 🏗️ Architecture
```
[Web UI :8580] → [API Gateway :5000] → [Order Service :5001] → [Payment Service :5002]
                                            ↓ (Kafka :9092)
                              [Notification Worker :5004, Inventory Worker :5005]

Telemetry: All Services → OTel Collector :4317 → [Prometheus :9090, Loki :3100, Tempo :3200]
                                                        ↓
                                                  Grafana :3000
```

## 📦 Services
| Port | Service | Role | DB |
|------|---------|------|-----|
| 5000 | api-gateway | BFF, routes requests | - |
| 5001 | order-service | Create orders, publish events | app_db + Redis |
| 5002 | payment-service | Process payments (simulated) | app_db |
| 5004 | notification-worker | Kafka consumer → notifications | app_db |
| 5005 | inventory-worker | Kafka consumer → stock mgmt | app_db |
| 5003 | traffic-gen | Load testing scenarios | - |

**Kafka topics:** `order.events` (order.created, order.payment_completed, order.payment_failed, stock.depleted)

## 🔭 Observability
- **Metrics:** Prometheus (scrape 15s) + OTel spanmetrics connector (auto RED metrics)
- **Logs:** Loki + Alloy (JSON structured, drop debug/health, extract trace_id/span_id)
- **Traces:** Tempo + OTel Collector (tail-sampling: 100% errors, 100% >500ms, 10% normal)
- **Dashboards:** App (RED method), Infra (USE), Kafka, SLO, Logging, Tracing, Alerting
- **Alerts:** MWMBR for SLOs (fast-burn 14.4x @ 5m+1h, slow-burn 3x @ 30m+6h), traffic guards enabled
- **SLOs:** API Gateway availability 99.5%, Payment success 99%, P95 latency <500ms

## 🎨 Key Conventions (Quick Reference)
- **Metric:** `{namespace}_{subsystem}_{name}_{unit}` snake_case (e.g., `orders_created_total`)
- **Service:** kebab-case (`order-service`, `inventory-worker`)
- **Kafka topic:** dot.notation (`order.events`, `order.shipping`, `<topic>.dlq`)
- **Span:** `<domain>.<operation>` (`catalog.fetch`, `inventory.check`, `kafka.produce`)
- **Log fields:** snake_case (`order_id`, `user_id`, `payment_txn_id`)
- **Error response:** RFC 7807 + `trace_id` + `error_code` (ERR_DOMAIN_PROBLEM)
- **Health:** `/health/live` (process only) + `/health/ready` (with DB/Cache/Kafka)
- **Alert severity:** critical (page, 1-5m) | warning (ticket, 5-30m) | info
- **Recording rules:** `{level}:{metric}:{operation}` (e.g., `service:request_rate:5m`)
- **Alert naming:** PascalCase `{Service}{Problem}` (e.g., `APIGatewayFastBurn`)

**⛔ Anti-patterns:**
- KHÔNG dùng high-cardinality labels trong metrics (user_id, request_id, http.url)
- KHÔNG check DB/Cache trong liveness probe (gây CrashLoopBackOff)
- KHÔNG log PII, KHÔNG dùng `print()`, KHÔNG thiếu `exc_info=True` khi log exception
- SLO alerts LUÔN cần traffic guard: `rate(total[5m]) > 0.1`

## 📚 When to Use What
| Task Type | Files to Paste | Est. Tokens |
|-----------|----------------|-------------|
| Quick PromQL / LogQL query | PROJECT_BRIEF.md only | ~1k |
| Debug 1 alert / 1 panel | PROJECT_BRIEF.md + alert/dashboard YAML | ~3-5k |
| Add new metric/log field | PROJECT_BRIEF.md + relevant source file | ~3-5k |
| Add new service / worker | PROJECT_BRIEF.md + CONVENTIONS.md | ~6k |
| Full architecture review | ARCHITECTURE.md + EXPANSION_PLAN.md | ~10k |
| Deep code review | CONVENTIONS.md + source files | ~8-15k |
| Runbook / break-test | CONVENTIONS.md + specific runbook file | ~8-12k |

## 🚀 Roadmap (Phase 1-6)
- **Phase 0:** Production readiness (health checks, RFC 7807, graceful shutdown, CI)
- **Phase 1:** Auth Service (JWT/RBAC) + TLS + Secrets management
- **Phase 2:** Shipping Service + Worker (Saga orchestrator, DLQ, compensation)
- **Phase 3:** Search Service (OpenSearch, CQRS, index aliasing)
- **Phase 4:** Advanced Obs (Saga tracing, synthetic monitoring, multi-ID correlation, business metrics)
- **Phase 5:** Chaos testing + SLO dashboards + DR drill
- **Phase 6:** Reliability gates (k6, Pact contract testing, Playwright E2E)

**New patterns coming:** Circuit Breaker, Rate Limiting, CQRS, Saga, Tail-based Sampling, Synthetic Monitoring

---
**Usage:** Paste file này ở đầu mỗi session Web Chat để AI có context ngay lập tức.