# 🏗️ Observability Lab — Architecture

> E-commerce microservices platform with event-driven architecture, full observability stack, and Kafka event streaming.

---
## Related Documents Quick Reference

| If you need to... | Go to... |
|-------------------|----------|
| Understand system design | This document |
| Handle an alert | [INCIDENT_RUNBOOK.md](INCIDENT_RUNBOOK.md) |
| Practice incident response | [INCIDENT_SIMULATION_GUIDE.md](INCIDENT_SIMULATION_GUIDE.md) |
| Understand component internals | [BREAK_TEST_RECOVERY.md](BREAK_TEST_RECOVERY.md) |
| Plan next expansion | [EXPANSION_PLAN.md](EXPANSION_PLAN.md) |
| Prepare for interview | [devops-question-senior.md](devops-question-senior.md) & [devops-question.md](devops-question.md)|

---
## Document Metadata

| Field | Value |
|-------|-------|
| **Document Status** | ✅ Reviewed & Approved |
| **Last Updated** | 2026-05-28 |
| **Version** | 2.1 (post-expansion planning) |
| **Owner** | Platform Engineering Team |
| **Author(s)** | dungtt, [Co-author if any] |
| **Reviewers** | [Principal Architect], [SRE Lead], [Security Team] |
| **Next Review** | 2026-08-28 (quarterly) |
| **Approval Date** | 2026-05-28 |

### Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-15 | dungtt | Initial architecture (6 services) |
| 2.0 | 2026-05-20 | dungtt | Added Network, Security, Capacity Planning, Failure Modes sections |
| 2.1 | 2026-05-28 | dungtt | Enhanced Mermaid diagrams, added metadata, cross-references |

### Related Architecture Decision Records (ADRs)

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| ADR-001 | Use KRaft instead of ZooKeeper for Kafka | ✅ Accepted | 2026-01-20 |
| ADR-002 | MinIO as S3-compatible storage for Loki/Tempo | ✅ Accepted | 2026-02-05 |
| ADR-003 | Separate Applications VM and Observability VM | ✅ Accepted | 2026-01-15 |
| ADR-004 | Gthread workers with deliberate connection pool queue | ✅ Accepted | 2026-03-10 |
| ADR-005 | Cache-aside pattern over write-through | ✅ Accepted | 2026-02-15 |
| ADR-006 | Pessimistic locking for inventory updates | ✅ Accepted | 2026-02-20 |
| ADR-007 | Idempotent consumers over exactly-once semantics | ✅ Accepted | 2026-03-01 |
| ADR-008 | OTel Collector as centralized telemetry pipeline | ✅ Accepted | 2026-02-10 |
| ADR-009 | Blackbox Exporter for 24/7 active probing | ✅ Accepted | 2026-03-15 |
| ADR-010 | Traffic guards on SLO burn rate alerts | ✅ Accepted | 2026-04-01 |

> **Note:** Xem chi tiết các ADRs trong [`docs/adrs/`](./docs/adrs/) (nếu có) hoặc trong git commit history.

### Document Scope

**In Scope:**
- Current architecture (6 services on Applications VM)
- Observability stack (Observability VM)
- Data flows (sync HTTP + async Kafka)
- Design patterns applied
- Security architecture (current state + planned)
- Capacity planning & resource allocation
- Failure modes & recovery procedures
- Operational considerations (backup, retention, upgrades)

**Out of Scope:**
- AWS deployment architecture (see separate repository)
- Terraform/IaC configurations
- Detailed API specifications (see OpenAPI specs)
- Database migration scripts
- CI/CD pipeline configurations (see `.github/workflows/`)

### Maintenance Guidelines

**When to Update This Document:**
- ✅ Adding new service or removing existing service
- ✅ Changing communication patterns (sync ↔ async)
- ✅ Modifying data layer (new database, cache strategy change)
- ✅ Updating security architecture (TLS, auth, secrets)
- ✅ Changing observability pipeline (new backend, sampling policy)
- ✅ Adjusting capacity planning (resource limits, pool sizing)
- ❌ Minor code refactoring (no architectural impact)
- ❌ Bug fixes (unless they reveal architectural gaps)

**Review Process:**
1. **Quarterly Review** (every 3 months): Full document review by owner + reviewers
2. **Ad-hoc Updates**: When architectural changes occur, update relevant sections immediately
3. **Version Bumping**: 
   - Patch (2.1 → 2.2): Minor clarifications, typo fixes
   - Minor (2.1 → 3.0): New sections, significant updates
   - Major (2.1 → 3.0): Architectural changes, new services

**Approval Workflow:**
1. Author updates document → creates PR
2. Reviewers comment and approve
3. Principal Architect final approval
4. Merge to main branch
5. Update "Last Updated" and "Version" fields

### References & Dependencies

**Internal Documents:**
- [INCIDENT_RUNBOOK.md](./INCIDENT_RUNBOOK.md) - Alert triage & recovery procedures
- [INCIDENT_SIMULATION_GUIDE.md](./INCIDENT_SIMULATION_GUIDE.md) - 12 incident simulation experiments
- [BREAK_TEST_RECOVERY.md](./BREAK_TEST_RECOVERY.md) - 28 break/test/recovery exercises
- [EXPANSION_PLAN.md](./EXPANSION_PLAN.md) - Roadmap to 10 services
- [devops-question-senior.md](./devops-question-senior.md) - Senior-level interview questions
- [devops-question.md](./devops-question.md) - junior and middle level interview questions

**External Standards:**
- [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) - Problem Details for HTTP APIs
- [W3C Trace Context](https://www.w3.org/TR/trace-context/) - Distributed tracing propagation
- [Google SRE Book](https://sre.google/sre-book/table-of-contents/) - SLO/SLI/Error Budget concepts
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/) - Telemetry standards

**Compliance & Security:**
- OWASP Top 10 (web application security)
- CIS Docker Benchmark (container hardening)
- NIST Cybersecurity Framework (incident response)

---
## System Architecture  

### High-Level Topology

```mermaid
graph TB
    subgraph "Applications VM (192.168.100.57)"
        UI["Web UI<br/>nginx :8580"]
        GW["API Gateway<br/>Flask :5000"]
        OS["Order Service<br/>Flask :5001"]
        PS["Payment Service<br/>Flask :5002"]
        TG["Traffic Generator<br/>:5003"]
        NW["Notification Worker<br/>:5004"]
        IW["Inventory Worker<br/>:5005"]
        PG[(PostgreSQL 16)]
        RD[(Redis 7)]
        KF[Kafka 3.7<br/>KRaft]
    end
    
    subgraph "Observability VM (192.168.100.55)"
        OTEL["OTel Collector<br/>:4317/:4318"]
        PROM[Prometheus]
        GRAF[Grafana]
        TEMPO[Tempo]
        LOKI[Loki]
        AM[Alertmanager]
        BB[Blackbox Exporter]
    end
    
    UI -->|reverse proxy| GW
    GW -->|HTTP| OS -->|HTTP| PS
    OS --> PG & RD & KF
    KF --> NW & IW
    NW & IW --> PG
    TG -->|load test| GW
    
    OS & GW & PS & NW & IW -->|OTLP| OTEL
    OTEL --> PROM & TEMPO & LOKI
    PROM --> GRAF & AM
    TEMPO & LOKI --> GRAF
    BB -->|probe /health/live| GW & OS & PS & NW & IW
    PROM -->|scrape| BB
```

### Synchronous Request Flow

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Web UI
    participant GW as API Gateway
    participant OS as Order Service
    participant PS as Payment Service
    participant DB as PostgreSQL
    participant RD as Redis
    
    U->>UI: Place Order
    UI->>GW: POST /order
    GW->>OS: POST /process
    OS->>RD: GET product:catalog
    alt Cache Hit
        RD-->>OS: Product data
    else Cache Miss
        OS->>DB: SELECT * FROM products
        DB-->>OS: Product data
        OS->>RD: SET product:catalog
    end
    OS->>PS: POST /charge
    PS-->>OS: Payment result
    OS->>DB: INSERT INTO orders
    OS-->>GW: Order response
    GW-->>UI: Order confirmation
    UI-->>U: Display result
```

### Asynchronous Event Flow

```mermaid
sequenceDiagram
    participant OS as Order Service
    participant KF as Kafka
    participant NW as Notification Worker
    participant IW as Inventory Worker
    participant DB as PostgreSQL
    
    OS->>KF: Publish order.created
    par Parallel Consumption
        KF-->>NW: Consume event
        NW->>NW: Idempotency check
        NW->>DB: INSERT notification
        NW->>KF: Commit offset
    and
        KF-->>IW: Consume event
        IW->>IW: Idempotency check
        IW->>DB: SELECT FOR UPDATE
        IW->>DB: UPDATE stock
        IW->>DB: INSERT inventory_log
        IW->>KF: Commit offset
    end
```

### Observability Pipeline

```mermaid
graph LR
    APP[All Services] -->|OTLP gRPC| OTEL[OTel Collector]
    
    OTEL -->|filter + tail sampling| TEMPO[Tempo]
    OTEL -->|spanmetrics connector| PROM[Prometheus]
    OTEL -->|app metrics| PROM
    
    ALLOY[Alloy Agent] -->|Docker + host logs| LOKI[Loki]
    
    BB[Blackbox Exporter] -->|HTTP probes| APP
    PROM -->|scrape every 15s| BB
    PROM -->|scrape| APP
    
    PROM --> GRAF[Grafana]
    TEMPO --> GRAF
    LOKI --> GRAF
    
    PROM -->|alerts| AM[Alertmanager]
    AM --> TG[Telegram]
    AM --> WH[Webhook Receiver]
```
---

## Network Architecture

### VM Specifications

| VM | IP | RAM | CPU | Disk | Role |
|----|-----|-----|-----|------|------|
| Applications VM | 192.168.100.57 | 60GB | 8 cores | 100GB | Business logic + Data layer |
| Observability VM | 192.168.100.55 | 32GB | 6 cores | 200GB | Monitoring stack |

### Network Segmentation

Hiện tại sử dụng **single Docker bridge network** (`observability`) cho tất cả services.

> **Production note:** Khi mở rộng (xem [EXPANSION_PLAN.md](EXPANSION_PLAN.md)), cần tách thành 4 networks:
> - `frontend` — Web UI, nginx
> - `backend` — API Gateway, services  
> - `data` — PostgreSQL, Redis, Kafka, OpenSearch
> - `observability` — OTel, Prometheus, Grafana (external)

### Port Exposure Strategy

| Type | Ports | Accessible From |
|------|-------|-----------------|
| **Exposed to host** | 8580 (Web UI), 3000 (Grafana), 8585 (Kafka UI) | External users |
| **Inter-VM (observability)** | 4317/4318 (OTLP), 9100 (node-exporter), 8080 (cadvisor), 9308 (kafka-exporter), 5003 (traffic-gen) | VM-to-VM only |
| **Internal service-to-service** | 5000-5005 (apps), 5432 (PostgreSQL), 6379 (Redis), 9092 (Kafka) | Docker network only |
| **Monitoring backends** | 9090 (Prometheus), 3100 (Loki), 3200 (Tempo) | Observability VM only |

### Firewall Rules (Required)

**Applications VM → Observability VM**
```
ALLOW 4317/tcp   # OTLP gRPC (traces + metrics)
ALLOW 4318/tcp   # OTLP HTTP (fallback)
```

**Observability VM → Applications VM**
```
ALLOW 9100/tcp       # node-exporter scrape
ALLOW 8080/tcp       # cadvisor scrape
ALLOW 9308/tcp       # kafka-exporter scrape
ALLOW 5003/tcp       # traffic-gen metrics
ALLOW 5000-5005/tcp  # Blackbox Exporter probes /health/live
```

**External → Applications VM**
```
ALLOW 8580/tcp   # Web UI
ALLOW 8585/tcp   # Kafka UI (dev only, restrict in production)
```

**External → Observability VM**
```
ALLOW 3000/tcp   # Grafana
```

### DNS Resolution

- **Docker embedded DNS** (`127.0.0.11`): Services resolve by container name
- **Nginx resolver config**: `resolver 127.0.0.11 valid=10s ipv6=off;`
  - Re-resolve upstream IPs every 10s
  - Prevents stale IP caching when containers rebuild

---

## Services

### Infrastructure

| Service | Image | Port | Description |
|---|---|---|---|
| **PostgreSQL** | `postgres:16-alpine` | 5432 | Primary database — orders, products, events, notifications, inventory |
| **Redis** | `redis:7-alpine` | 6379 | Cache layer — product catalog (TTL 60s) |
| **Kafka** | `apache/kafka:3.7.0` | 9092 | Event streaming platform — KRaft mode (no ZooKeeper) |
| **Kafka Exporter** | `danielqsj/kafka-exporter` | 9308 | Exports Kafka metrics → Prometheus |
| **Kafka UI** | `provectuslabs/kafka-ui` | 8585 | Web UI for Kafka topic/consumer inspection |

### Application Services

| Service | Port | Description |
|---|---|---|
| **Web UI** | 8580 | Nginx SPA — dashboard, orders, events, load testing |
| **API Gateway** | 5000 | BFF pattern — routes, aggregates, error propagation |
| **Order Service** | 5001 | Create orders, manage payments, publish Kafka events |
| **Payment Service** | 5002 | Simulated payment processing with configurable latency/errors |
| **Traffic Generator** | 5003 | Load testing tool with scenario templates (flash sale, pipeline) |
| **Notification Worker** | 5004 | Kafka consumer — processes order events → sends notifications |
| **Inventory Worker** | 5005 | Kafka consumer — processes order events → manages stock |

### Observability Stack (Separate VM)

| Tool | Port | Description |
|---|---|---|
| **OTel Collector** | 4317/4318 | Receives OTLP traces/metrics/logs, routes to backends |
| **Prometheus** | 9090 | Metrics storage, PromQL, recording rules, alerting rules |
| **Grafana** | 3000 | Dashboards — application health, Kafka, workers, SLO |
| **Tempo** | 3200 | Distributed tracing backend |
| **Loki** | 3100 | Log aggregation with LogQL |
| **Alertmanager** | 9093 | Alert routing → Telegram |
| **Blackbox Exporter** | 9115 | Active probing — HTTP health checks to service `/health/live` endpoints |

---

## Data Flow

### Synchronous (HTTP Request Path)
```
Web UI → API Gateway → Order Service → Payment Service
                              ↕              
                         PostgreSQL     
                              ↕              
                           Redis (cache)
```

### Asynchronous (Event-Driven Path)
```
Order Service ──publish──► Kafka (topic: order.events)
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
           Notification Worker     Inventory Worker
           (group: notif-workers)  (group: inv-workers)
                    │                     │
                    ▼                     ▼
              notifications         inventory_log
              (PostgreSQL)          (PostgreSQL)
```

### Kafka Event Types

| Event | Trigger | Consumed By |
|---|---|---|
| `order.created` | New order saved | Notification Worker, Inventory Worker |
| `order.payment_completed` | Payment success | Notification Worker |
| `order.payment_failed` | Payment rejected | Notification Worker, Inventory Worker |
| `stock.depleted` | Stock insufficient (< threshold) | Inventory Worker (triggers auto-restock) |

### Telemetry Pipeline
```
All Services ──OTLP gRPC──► OTel Collector ──► Prometheus (metrics)
                                            ──► Tempo (traces)
                                            ──► Loki (logs)
                                            ──► Grafana (dashboards)

Blackbox Exporter ──probe /health/live──► Application Services
Prometheus ──scrape──► Blackbox Exporter (probe results)
```

---

## Database Schema

```mermaid
erDiagram
    orders {
        serial id PK
        varchar order_id UK
        integer product_id FK
        varchar product_name
        integer quantity
        decimal total_amount
        varchar status
        varchar payment_txn_id
        timestamp created_at
        timestamp updated_at
    }

    products {
        serial id PK
        varchar name
        decimal price
        integer stock
        varchar category
    }

    processed_events {
        varchar event_id PK
        varchar event_type
        varchar processed_by PK
        timestamp processed_at
    }

    notifications {
        serial id PK
        varchar event_id
        varchar order_id
        varchar notification_type
        varchar channel
        varchar status
        timestamp created_at
    }

    inventory_log {
        serial id PK
        varchar event_id
        varchar order_id
        integer product_id
        varchar action
        integer quantity
        integer stock_before
        integer stock_after
        timestamp created_at
    }

    orders ||--o{ notifications : "order_id"
    orders ||--o{ inventory_log : "order_id"
    products ||--o{ inventory_log : "product_id"
    processed_events ||--o| notifications : "event_id"
    processed_events ||--o| inventory_log : "event_id"
```
---

## Capacity Planning

### Resource Allocation (per service)

| Service | CPU Limit | Memory Limit | Workers/Threads | Rationale |
|---------|-----------|--------------|-----------------|-----------|
| API Gateway | 1.0 | 512MB | 2 workers × 8 threads | High concurrency, stateless |
| Order Service | 1.0 | 512MB | 2 workers × 8 threads | DB + Redis + Kafka I/O bound |
| Payment Service | 0.5 | 256MB | 4 workers (sync) | Stateless, simulated latency |
| Notification Worker | 0.5 | 256MB | 1 worker + consumer thread | Kafka consumer single-threaded |
| Inventory Worker | 0.5 | 256MB | 1 worker + consumer thread | Kafka consumer + pessimistic locking |
| PostgreSQL | 2.0 | 2GB | — | Shared DB, connection pooling |
| Redis | 1.0 | 1GB | — | Cache only, TTL 60s |
| Kafka | 2.0 | 4GB | — | KRaft mode, 3 partitions |
| OpenSearch (planned) | 2.0 | 3GB | — | JVM heap 1GB + OS overhead |

### Connection Pool Sizing

**Formula (PostgreSQL standard):**

```
max_connections = (core_count × 2) + effective_spindle_count
```

**Current configuration:**

- Order Service: 2 workers × 8 threads = **16 concurrent requests**
- Connection pool max: **10 connections** (conservative)
- Result: 6 requests queue on `getconn()` during peak → latency stacking

**Trade-off rationale:**

- Pool max = 10 (not 16) để avoid DB overload
- Under load: queue wait time < request timeout (30s)
- When pool exhausted → requests timeout → `HighLatencyP95` alert → investigate

**Production sizing (with PgBouncer):**

```
App → PgBouncer (transaction mode) → PostgreSQL
  App pool:              20 connections per service
  PgBouncer pool:       100 connections total
  PostgreSQL max_connections: 120 (100 + 20 reserved for admin)
```

### Kafka Partition Strategy

| Topic | Partitions | Replication | Consumer Groups | Rationale |
|-------|-----------|-------------|-----------------|-----------|
| `order.events` | 3 | 1 (lab) | 2 (notification, inventory) | Balance parallelism vs resources |

**Partition assignment:**

- Key: `order_id` (hashed) → same order always goes to same partition
- 3 partitions = max 3 consumers per group
- Lab: single broker → replication factor 1
- Production: 3 brokers → replication factor 3, min ISR 2

**Consumer lag thresholds:**

- Warning: lag > 100 messages (5m)
- Critical: lag > 1000 messages (3m)
- Group down: 0 active members (5m)

### Prometheus Capacity

| Metric | Current | Production Target |
|--------|---------|-------------------|
| Scrape interval | 15s | 15s |
| Retention | 15 days | 30 days local + remote (Thanos) |
| Active series | ~5K | ~50K (with cardinality controls) |
| TSDB size | ~500MB | ~5GB |

**Cardinality guardrails:**

- Max labels per metric: 10
- Blacklist labels: `user_id`, `request_id`, `session_id`
- Allowed high-cardinality: only in logs (Loki), traces (Tempo)

---

## Design Patterns

### 1. Event-Driven Architecture
Order Service publishes events to Kafka after completing operations. Workers consume events independently, enabling loose coupling and horizontal scaling.
```
Order Service → Kafka → [Notification Worker, Inventory Worker]
```
- **Loose coupling**: Order service không cần biết về notification hay inventory logic
- **Scalability**: Mỗi consumer group có thể scale độc lập
- **Resilience**: Nếu worker down, message vẫn nằm trong Kafka chờ xử lý

### 2. Idempotent Processing
Workers track processed events in `processed_events` table using composite key `(event_id, processed_by)`. Prevents duplicate processing on Kafka redelivery.
```sql
-- Check before processing:
SELECT 1 FROM processed_events WHERE event_id = %s AND processed_by = %s
-- After processing:
INSERT INTO processed_events (event_id, event_type, processed_by) VALUES (...)
```

### 3. Cache-Aside (Redis)
Product catalog is cached in Redis with 60s TTL. Order Service checks cache first, falls back to PostgreSQL on cache miss, then populates cache.
- Custom metrics: `cache_hit_total`, `cache_miss_total`

### 4. Pessimistic Locking (Inventory)
```sql
SELECT stock FROM products WHERE id = %s FOR UPDATE;  -- Acquire row lock
UPDATE products SET stock = %s WHERE id = %s;          -- Update stock
INSERT INTO inventory_log (...);                       -- Audit trail
COMMIT;                                                -- Release lock
```

### 5. Distributed Trace Propagation
Trace context (W3C `traceparent`) is injected into Kafka message headers by producers and extracted by consumers, enabling end-to-end distributed tracing across async boundaries.

### 6. Backend for Frontend (BFF)
API Gateway aggregates calls to backend services and handles error propagation, providing a unified API for the Web UI.
```
/api/*            → api-gateway:5000
/notifications/*  → notification-worker:5004
/inventory/*      → inventory-worker:5005
/traffic/*        → traffic-gen:5003
```
### 7. Multi-Stage Docker Builds

Tất cả Python services dùng multi-stage build để giảm image size và attack surface:

```dockerfile
# Stage 1: Build dependencies (isolated)
FROM python:3.12-slim-bookworm AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile --prefix=/install -r requirements.txt

# Stage 2: Runtime (minimal image)
FROM python:3.12-slim-bookworm
RUN groupadd -r appuser && useradd -r -g appuser -s /usr/sbin/nologin appuser
COPY --from=builder /install /usr/local
COPY app.py .
USER appuser
CMD ["gunicorn", "--workers", "2", "--threads", "8", "--bind", "0.0.0.0:5001", "app:app"]
```

**Benefits:**

- Runtime image ~150MB (vs ~400MB single-stage)
- No build tools (`pip`, `gcc`) in production image
- Reduced CVE surface
- Works with read-only filesystem

### 8. Health Check Pattern (Liveness vs Readiness)

Mỗi service expose 2 endpoints chuẩn Kubernetes/ECS:

```python
from shared.health import create_health_blueprint

health_bp = create_health_blueprint("order-service", checks={
    "db": lambda: db.check_health(),
    "cache": lambda: cache.check_health(),
    "kafka": lambda: kafka_producer.list_topics(timeout=5),
})
app.register_blueprint(health_bp)
```

**Endpoints:**

- `GET /health/live` — Liveness: process alive? Always 200 unless crashed
- `GET /health/ready` — Readiness: can handle traffic? Checks all dependencies
- `GET /health` — Alias của readiness (backward compatibility)

**Response format:**

```json
{
  "status": "ready",
  "service": "order-service",
  "uptime_seconds": 3600.5,
  "checks": {
    "db": "ok",
    "cache": "ok",
    "kafka": "ok"
  }
}
```

**Usage:**

- Docker Compose: `healthcheck` directive
- Blackbox Exporter: probe `/health/live` every 15s
- Future K8s: liveness/readiness probes

### 9. Structured Logging Pattern

Tất cả services dùng JSON logging với correlation IDs:

```python
from shared.logging_config import setup_logging

logger = setup_logging("order-service")

logger.info("Order created", extra={
    "order_id": order_id,
    "product_id": product_id,
    "amount": total_amount,
    "trace_id": trace_id  # auto-injected by OTel LoggingInstrumentor
})
```

**Output format:**

```json
{
  "timestamp": "2026-05-28T10:30:45.123Z",
  "level": "info",
  "logger": "order-service",
  "message": "Order created",
  "order_id": "abc123",
  "product_id": 5,
  "amount": 99.99,
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "a3ce929d0e0e4736"
}
```

**Rules:**

- Always use `extra={}` dict for context
- Never use f-string in log message
- Log levels: `DEBUG` (dev), `INFO` (normal), `WARNING` (degraded), `ERROR` (failures)
- Auto-injected: `timestamp`, `level`, `trace_id`, `span_id`

### 10. RFC 7807 Error Response Pattern

Chuẩn hóa error responses theo RFC 7807 (Problem Details):

```python
from shared.errors import problem_response

@app.route("/process", methods=["POST"])
def process_order():
    # ... validation ...
    
    if product_not_found:
        return problem_response(
            status=404,
            title="Product Not Found",
            detail=f"Product with id {product_id} does not exist",
            instance="/process",
            extra={"order_id": order_id, "product_id": product_id}
        )
```

**Response format:**

```json
{
  "type": "about:blank",
  "title": "Product Not Found",
  "status": 404,
  "detail": "Product with id 999 does not exist",
  "instance": "/process",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "order_id": "abc123",
  "product_id": 999
}
```

**Benefits:**

- Consistent error format across all services
- `trace_id` enables correlation with distributed traces
- Machine-readable for API clients
- Standard (RFC 7807) → familiar to developers

### 11. Graceful Shutdown Pattern (Kafka Consumers)

Kafka consumers phải xử lý `SIGTERM` đúng để commit offsets:

```python
import signal
import sys

consumer_running = True

def shutdown_handler(signum, frame):
    global consumer_running
    sig_name = signal.Signals(signum).name
    logger.info(f"Received {sig_name}, shutting down gracefully...",
                extra={"signal": sig_name})
    consumer_running = False

signal.signal(signal.SIGTERM, shutdown_handler)
signal.signal(signal.SIGINT, shutdown_handler)

# Consumer loop checks consumer_running flag
while consumer_running:
    msg = consumer.poll(timeout=1.0)
    # ... process message ...

# Cleanup
consumer.close()  # Commit final offsets
db_connection.close()
logger.info("Consumer stopped cleanly")
```

**Docker Compose config:**

```yaml
services:
  notification-worker:
    stop_grace_period: 30s  # Wait before SIGKILL
```

**Why critical:**

- Kill consumer mid-processing → duplicate processing on restart
- Saga state inconsistency if worker dies during compensation
- Offset commit ensures no message loss or duplicate
---
## Security Architecture

### Current State (Lab Environment)

> ⚠️ **Lab-only configuration** — không áp dụng cho production

| Aspect | Current Implementation |
|--------|------------------------|
| Authentication | ❌ None (all APIs public) |
| Authorization | ❌ None |
| Encryption | ❌ HTTP only (no TLS) |
| Secrets | ⚠️ Environment variables in `docker-compose.yml` |
| Network | ⚠️ Single bridge network (no segmentation) |

### Container Hardening (Applied)

Tất cả application containers đều áp dụng security best practices:

```yaml
# All application containers (api-gateway, order-service, workers...)
read_only: true                    # Read-only root filesystem
tmpfs:
  - /tmp                           # Writable tmpfs for temp files
cap_drop:
  - ALL                            # Drop all Linux capabilities
security_opt:
  - no-new-privileges:true         # Prevent privilege escalation
user: appuser                      # Non-root user (UID 1000)
```

> **Exception:** `web-ui` (nginx) không dùng `read_only: true` vì entrypoint scripts cần write `/etc/nginx/conf.d/` khi startup. Vẫn enforce `cap_drop: ALL` + `no-new-privileges`.

### Planned Security Improvements (Production)

Xem chi tiết trong [EXPANSION_PLAN.md](EXPANSION_PLAN.md):

| Improvement | Implementation | Priority |
|-------------|---------------|----------|
| TLS termination | nginx + self-signed certs (lab) / ACM (AWS) | P0 |
| JWT authentication | Auth Service + local public key verification | P0 |
| RBAC | User roles: customer, admin, service | P1 |
| Secrets management | Docker secrets + `.env` files (not in git) | P0 |
| Network segmentation | 4 Docker networks (frontend, backend, data, observability) | P1 |
| Resource limits | CPU/memory limits per container | P1 |
| Log rotation | `json-file` driver, max-size 10MB, max-file 3 | P1 |

### Secrets Management Strategy

**Current (lab):**

```yaml
# docker-compose.yml
environment:
  - DATABASE_URL=postgresql://app:app_secret@postgres:5432/orders
```

**Planned (production):**

```yaml
# docker-compose.yml
secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_public_key:
    file: ./secrets/jwt_public.pem

services:
  order-service:
    secrets:
      - db_password
      - jwt_public_key
```

**Rules:**

- `.env.*` và `secrets/` trong `.gitignore`
- File permissions: `chmod 600`
- JWT key rotation: publish new public key trước, rotate private key sau
---
## Failure Modes & Recovery

### Single Points of Failure (SPOF)

| Component | Impact if Down | MTTD | MTTR | Mitigation |
|-----------|----------------|------|------|------------|
| **PostgreSQL** | All writes fail, orders blocked | < 1 min | 5-10 min | Connection pooling, health checks, daily backups |
| **Kafka** | Async flows stop (notifications, inventory) | < 1 min | 2-5 min | Consumer lag monitoring, 7-day retention |
| **Redis** | Cache misses, DB overload | < 1 min | 1-2 min | Cache-aside graceful degradation |
| **OTel Collector** | No new traces/metrics/logs | < 1 min | 1-2 min | SDK retry with exponential backoff |
| **Prometheus** | No alerting, dashboards stale | < 1 min | 5 min | Alertmanager independent, watchdog alert |

### Expected Behavior on Failure

| Failure Scenario | System Response | User Impact | Detection |
|------------------|-----------------|-------------|-----------|
| **Payment Service down** | Order returns `payment_error` status | Order created but unpaid | `ServiceHealthCheckFailed` + `PaymentFastBurn` |
| **Kafka down** | Orders created, no notifications/inventory | Delayed confirmations | `KafkaExporterDown` + consumer lag alerts |
| **Redis down** | All requests hit DB, latency 5-10x slower | Slow response times | `HighLatencyP95` + cache hit rate = 0% |
| **DB pool exhausted** | Requests queue, timeout after 30s | 504 Gateway Timeout | `HighLatencyP95` + pool utilization > 80% |
| **OTel Collector down** | Apps retry, no telemetry collected | Monitoring blind spot | `TargetDown` on otel-collector job |
| **Nginx DNS stale** | 502 Bad Gateway after container rebuild | Partial outage | Web UI health badge = DOWN |

### Data Durability Guarantees

| Component | Durability Mechanism | RPO | RTO |
|-----------|---------------------|-----|-----|
| **PostgreSQL** | ACID compliant, WAL for crash recovery, daily `pg_dump` | 24h (daily backup) | 30 min |
| **Kafka** | `acks=all` producer config, 7-day retention | 0 (replicated) | 5 min |
| **Redis** | RDB snapshots every 15 min, AOF disabled (cache-only) | 15 min (cache rebuild OK) | 1 min |
| **Loki logs** | MinIO (S3) backend, 7-day retention | 0 | 10 min |
| **Tempo traces** | MinIO (S3) backend, 7-day retention | 0 | 10 min |
| **Prometheus metrics** | TSDB local, 15-day retention | 0 (short-term OK) | 15 min |

### Cascading Failure Patterns

**Pattern 1: DB saturation cascade**

```
DB lock → connection pool exhausted → order-service timeout
  → API Gateway 504 → user retry → more DB load → death spiral
```

> **Mitigation:** Circuit breaker (planned), connection pool sizing, `statement_timeout`

**Pattern 2: Kafka consumer lag cascade**

```
Worker slow → consumer lag grows → events pile up
  → worker finally catches up → burst of DB writes → DB saturation
```

> **Mitigation:** Consumer lag alerts (leading indicator), worker horizontal scaling

**Pattern 3: Cache-miss storm**

```
Redis restart → cache empty → all requests hit DB
  → DB overloaded → P95 latency spike → timeouts
```

> **Mitigation:** Cache warming script after Redis restart, DB capacity for 100% traffic
---

## Monitoring & Alerting

### Prometheus Scrape Targets
- `kafka-exporter:9308` — Kafka broker metrics
- OTel Collector → forward metrics từ tất cả services
- Blackbox Exporter → active health check probes

### Alert Rules

| Category | Rules | Description |
|---|---|---|
| **Kafka** | `KafkaConsumerLagHigh`, `KafkaTopicUnderReplicated`, `KafkaConsumerGroupDown` | Consumer lag, partition health, group status |
| **SLO Burn Rate** | `APIGateway*BurnRate`, `PaymentService*BurnRate` | Fast-burn (2m/15m) and slow-burn (30m/3h) windows |
| **Health Check** | `ServiceHealthCheckFailed` | Blackbox Exporter probe failure > 1 minute |
| **Predictive** | `DiskSpacePrediction`, `MemoryUsagePrediction` | `predict_linear()` based forecasting |

### Traffic Guards
- SLO burn rate alerts include `rate(total[5m]) > 0` condition
- Prevents **phantom alerts** when stale metrics persist after traffic stops
- Recording rules use `or vector(1)` fallback, but traffic guards are still needed for alert accuracy

### Grafana Dashboards
- **Alerting Overview**: Firing alerts, alert history
- **Unified Overview**: Cross-service RED metrics at a glance
- **App Performance**: Per-service request rate, error rate, latency (RED method)
- **SLO Overview**: Availability/Latency compliance, burn rate, error budget
- **Kafka Overview**: Topic throughput, consumer lag, partition distribution
- **Worker Performance**: Processing rate, errors, duration histograms
- **Infrastructure**: Node Exporter, cAdvisor, DB connections

---

## Environment Variables

| Variable | Used By | Description |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | All services | OTel Collector endpoint (Observability VM) |
| `DATABASE_URL` | Order, Notification, Inventory | PostgreSQL connection string |
| `REDIS_URL` | Order Service | Redis connection string |
| `KAFKA_BOOTSTRAP_SERVERS` | Order, Notification, Inventory | Kafka broker address |
| `ORDER_SERVICE_URL` | API Gateway | Order Service endpoint |
| `PAYMENT_SERVICE_URL` | Order Service | Payment Service endpoint |

---

## Ports Summary

| Port | Service | Protocol |
|---|---|---|
| 5000 | API Gateway | HTTP |
| 5001 | Order Service | HTTP |
| 5002 | Payment Service | HTTP |
| 5003 | Traffic Generator | HTTP |
| 5004 | Notification Worker | HTTP |
| 5005 | Inventory Worker | HTTP |
| 5432 | PostgreSQL | TCP |
| 6379 | Redis | TCP |
| 8580 | Web UI | HTTP |
| 8585 | Kafka UI | HTTP |
| 9092 | Kafka | TCP |
| 9115 | Blackbox Exporter | HTTP |
| 9308 | Kafka Exporter | HTTP |

---
## Key Design Decisions

### Why KRaft instead of ZooKeeper?

- **Simplified deployment:** Single binary, no separate ZooKeeper cluster
- **Faster controller failover:** Metadata stored in Kafka itself
- **Production trend:** ZooKeeper deprecated in Kafka 3.0+ (KIP-500)
- **Learning value:** Modern Kafka deployment pattern

### Why MinIO instead of local filesystem?

- **Production-like:** S3-compatible API (same as AWS S3)
- **Scalability:** Easy migration path to AWS S3
- **Shared storage:** Both Loki and Tempo use same backend
- **Cost-effective:** Single storage layer for logs + traces

### Why 2 separate VMs?

- **Resource isolation:** Observability stack doesn't compete with app resources
- **Failure domain separation:** App crash doesn't take down monitoring
- **Network security:** Different firewall rules per VM
- **AWS mapping:** Separate EC2 instances or EKS node groups

### Why gthread workers (not sync/gevent)?

- **I/O bound workloads:** DB queries, HTTP calls, Kafka I/O benefit from threading
- **Memory efficiency:** Threads share memory (vs processes)
- **GIL not a bottleneck:** Most time spent waiting on I/O, not CPU
- **Trade-off:** 2 workers × 8 threads = 16 concurrent, but pool max = 10 → deliberate queue

### Why cache-aside (not write-through)?

- **Simplicity:** App controls cache invalidation explicitly
- **Flexibility:** Different TTLs for different data (60s for catalog, 5m for user sessions)
- **Graceful degradation:** Cache miss → DB query (slower but works)
- **Observability:** Clear cache hit/miss metrics

### Why pessimistic locking (not optimistic)?

- **Inventory use case:** Stock updates are high-contention
- **Data consistency:** `SELECT FOR UPDATE` prevents race conditions
- **Simplicity:** No retry logic needed (vs optimistic with version conflicts)
- **Trade-off:** Lower throughput, but acceptable for inventory operations

### Why idempotent consumers (not exactly-once)?

- **Simplicity:** `processed_events` table check before processing
- **Kafka reality:** `at-least-once` is default, exactly-once requires transactions
- **Business logic:** Duplicate notification/stock update is acceptable, lost event is not
- **Trade-off:** Small storage overhead (processed_events table)

### Why OTel Collector (not direct export)?

- **Centralized processing:** Tail-based sampling, filtering, transformation
- **Protocol flexibility:** Apps send OTLP, collector fans out to multiple backends
- **Cost control:** Drop health check spans, sample 10% of normal traces
- **Operational:** Single point to update sampling policies

### Why Blackbox Exporter (not just span metrics)?

- **24/7 detection:** Active probing works at 3 AM with no user traffic
- **Complementary:** Span metrics need traffic, Blackbox doesn't
- **SLA monitoring:** Probe from outside, like real users
- **Phantom alert prevention:** Distinguishes "service down" vs "no traffic"

### Why traffic guards on SLO alerts?

- **Problem:** `rate(errors[1h]) / rate(total[1h])` stays high when traffic = 0
- **Example:** 3 errors out of 3 requests = 100% error rate, but only 3 requests!
- **Solution:** Add `rate(total[5m]) > 0.1` condition
- **Trade-off:** May miss real incidents during very low traffic (acceptable)

---
## Operational Considerations

### Backup Strategy

| Component | Method | Frequency | Retention | RTO | RPO | Verification |
|-----------|--------|-----------|-----------|-----|-----|--------------|
| PostgreSQL | `pg_dump` | Daily 2 AM | 7 days | 30 min | 24h | Monthly restore drill |
| Kafka topics | Retention policy | Continuous | 7 days | N/A | 0 | Consumer lag monitoring |
| Grafana | Dashboards as code | Git commit | Forever | 5 min | 0 | PR review |
| Prometheus | TSDB snapshots | Weekly | 4 weeks | 15 min | 7 days | Snapshot restore test |
| Loki/Tempo | MinIO versioning | Continuous | 7 days | 10 min | 0 | S3 bucket audit |

**Backup commands:**

```bash
# PostgreSQL (per-database, hybrid strategy)
pg_dump -h localhost -U app_user app_db > backup/app_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U auth_user auth_db > backup/auth_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U shipping_user shipping_db > backup/shipping_db_$(date +%Y%m%d).sql

# Verify backup integrity (dry-run)
pg_restore --list backup/app_db_20260528.sql

# Prometheus TSDB snapshot
curl -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot
```

### Log & Metrics Retention

| Data Type | Storage | Retention | Rationale |
|-----------|---------|-----------|-----------|
| Application logs | Loki (MinIO) | 7 days | Debug window, storage cost |
| Host logs | Loki (MinIO) | 7 days | Security audit |
| Docker logs | `json-file` driver | 10MB × 3 files | Prevent disk fill |
| Prometheus metrics | TSDB local | 15 days | Short-term analysis |
| Traces | Tempo (MinIO) | 7 days | Debug window |
| Grafana dashboards | Git | Forever | Version control |

### Upgrade Procedures

**Zero-downtime deployment (future with K8s/ECS):**

- Rolling update with health checks
- Blue-green deployment for DB migrations
- Canary deployment for risky changes

**Current (Docker Compose):**

```bash
# Brief downtime during `docker compose up -d`
# Use depends_on with health checks to minimize impact

# Safe upgrade sequence:
docker compose pull
docker compose up -d --no-deps postgres  # DB first
docker compose up -d --no-deps redis
docker compose up -d --no-deps kafka
docker compose up -d  # Apps last, with health check dependencies
```

**Database migration strategy:**

- Write migration SQL (backward compatible)
- Test on staging with production-sized data
- Apply during low-traffic window
- Monitor `pg_stat_activity` for lock contention
- Have rollback script ready (if possible)

### Capacity Planning Triggers

| Signal | Action | Timeline |
|--------|--------|----------|
| CPU > 70% sustained 1h | Investigate, plan scaling | 1 week |
| Memory > 80% sustained 1h | Add memory or optimize | 1 week |
| Disk > 70% | Clean up or expand | 3 days |
| DB connections > 80% pool | Add PgBouncer or tune | 2 weeks |
| Kafka lag > 1000 sustained | Scale consumer group | 1 week |
| Prometheus series > 50K | Reduce cardinality | 2 weeks |

### On-Call Procedures

Xem chi tiết tại [INCIDENT_RUNBOOK.md](INCIDENT_RUNBOOK.md#escalation-matrix):
- Escalation matrix (Team Lead → Engineering Manager → VP Eng)
- Communication templates (Initial/Update/Resolution)
- Post-incident process (blameless post-mortem trong 48h)

---
## DevOps Knowledge Applied

### Containerization & Orchestration

| Skill | Details |
|---|---|
| **Docker Compose** | Multi-service orchestration, `depends_on` + `condition`, health checks |
| **Health Checks** | `pg_isready`, `redis-cli ping`, Kafka broker API check |
| **Networking** | Docker external network, DNS resolution between containers |
| **Volume Management** | Data persistence for PostgreSQL, Kafka |

### Message Streaming (Kafka)

| Skill | Details |
|---|---|
| **KRaft Mode** | Kafka without ZooKeeper, simplified deployment |
| **Topic Design** | Key-based partitioning (`order_id`), 3 partitions |
| **Consumer Groups** | `notification-workers`, `inventory-workers` — independent consumption |
| **Monitoring** | kafka-exporter → Prometheus, consumer lag tracking |

### Reliability Patterns

| Pattern | Implementation |
|---|---|
| **Idempotent Processing** | `processed_events` table, check before processing |
| **Graceful Degradation** | Kafka publish failure does not block order creation |
| **Retry Logic** | Kafka producer `retries: 3`, `retry.backoff.ms: 100` |
| **Audit Trail** | `inventory_log` table records all stock changes |
| **Health Endpoints** | Each service exposes `/health/live` and `/status` |

### Debugging & Troubleshooting

| Scenario | Skills Applied |
|---|---|
| "Unknown error" on order creation | Trace API response format across layers (UI → Gateway → Service) |
| Events tab empty | Compare API response fields vs UI expectations (contract mismatch) |
| Worker DB errors | Understand `init.sql` only runs once when volume is first created |
| Kafka topic not created | Auto-create happens only when producer sends first message |
| Phantom alerts at night | Check traffic rate before investigating SLO burn rate alerts |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    CI/CD & Deployment                        │
│  Docker Compose → Build → Deploy → Health Check → Monitor   │
├─────────────────────────────────────────────────────────────┤
│                    Observability Stack                       │
│  Metrics (Prometheus) + Logs (Loki) + Traces (Tempo)        │
│  → Correlation → Dashboards (Grafana) → Alerts (Telegram)  │
├─────────────────────────────────────────────────────────────┤
│                    Application Layer                         │
│  API Gateway → Order → Payment (sync HTTP)                  │
│  Order → Kafka → Workers (async event-driven)               │
│  OTel SDK instrumentation for all services                  │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer                                │
│  PostgreSQL (persistence) + Redis (cache) + Kafka (events)  │
└─────────────────────────────────────────────────────────────┘
```

> [!TIP]
> 💡 **Key takeaway**: Observability is not just "viewing metrics" — it's the ability to **trace a request end-to-end** through the entire system (HTTP → Kafka → Worker → Database), combining 3 signals (Metrics + Logs + Traces) to **debug faster** and **detect issues before users are impacted**.

