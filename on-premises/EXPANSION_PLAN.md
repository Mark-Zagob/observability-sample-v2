# 📐 Kế Hoạch Mở Rộng Ứng Dụng

> Đề xuất mở rộng hệ thống e-commerce từ 6 services lên 10 services, tập trung vào **architectural diversity** để maximize kiến thức DevOps/SRE/Platform khi deploy lên AWS.

---

## Mục Tiêu

| # | Mục tiêu | Đo lường |
|---|---------|---------|
| 1 | Tăng **architectural diversity** | Thêm ≥ 3 communication patterns mới |
| 2 | Tạo **failure scenarios phức tạp hơn** | Cascading failures qua ≥ 4 services |
| 3 | Học thêm **design patterns production-grade** | Saga, CQRS, Circuit Breaker |
| 4 | Giữ chi phí AWS hợp lý | Không tăng quá 40% so với hiện tại |

---

## Hiện Trạng (6 Services)

```
Web UI → API Gateway → Order Service → Payment Service
                              ↕                ↕
                         PostgreSQL          Redis
                              ↕
                           Kafka
                         ↙      ↘
            Notification Worker  Inventory Worker
```

**Patterns đã có:**
- ✅ Sync HTTP (request-response)
- ✅ Async Event-driven (Kafka pub/sub)
- ✅ Cache-Aside (Redis)
- ✅ BFF (API Gateway)
- ✅ Idempotent Processing (processed_events table)
- ✅ Pessimistic Locking (SELECT FOR UPDATE)
- ✅ Distributed Trace Propagation (W3C traceparent qua Kafka headers)

**Thiếu:**
- ❌ Saga pattern (distributed transaction)
- ❌ Circuit Breaker (failure isolation)
- ❌ CQRS/Data sync (read model khác write model)
- ❌ Authentication/Authorization (JWT propagation)
- ❌ Health check endpoint chuẩn (liveness/readiness)
- ❌ Rate limiting
- ❌ Structured error response chuẩn (RFC 7807)
- ❌ TLS termination (HTTPS)
- ❌ Secrets management (JWT keys, DB passwords)
- ❌ Network segmentation (Docker networks per tier)
- ❌ Resource limits (CPU/memory per container)
- ❌ Backup/Restore procedures
- ❌ Graceful shutdown (Kafka consumers)
- ❌ Log rotation & retention
- ❌ CI pipeline (lint, test, build)
- ❌ Horizontal scaling (multiple instances + load balancing)

---

## Database Strategy

### Approach: Hybrid (1 Instance, Multiple Databases)

Không dùng shared database (tất cả dùng chung 1 DB), cũng không dùng database-per-instance (mỗi service 1 PostgreSQL riêng). Thay vào đó: **1 PostgreSQL instance, nhiều databases tách biệt theo domain**.

```
PostgreSQL instance (:5432)
  ├── app_db          ← Order, Payment, Inventory, Notification (shared — cùng domain)
  ├── auth_db         ← Auth Service (riêng — sensitive credentials)
  └── shipping_db     ← Shipping Service + Worker (riêng — khác lifecycle)

Redis (:6379)         ← Cache (shared, tất cả services)
OpenSearch (:9200)    ← Search Service (riêng)
```

### Tại sao Hybrid?

| Quyết định | Lý do |
|-----------|-------|
| **app_db shared** | Order, Payment, Inventory cần JOIN bảng `orders` + `products`. Tách ra = phải sync qua event, phức tạp không cần thiết |
| **auth_db riêng** | User credentials (password hash) PHẢI tách biệt — security best practice. Không service nào nên truy cập trực tiếp bảng users |
| **shipping_db riêng** | Khác domain, khác lifecycle. Shipping có thể deploy/migrate schema độc lập mà không ảnh hưởng orders |
| **OpenSearch riêng** | Khác engine hoàn toàn — optimized cho full-text search, không phải relational data |

### DevOps/SRE Learning Value

| Skill | Với Hybrid approach |
|-------|--------------------|
| **Backup/Restore** | Backup từng database riêng: `pg_dump app_db`, `pg_dump auth_db` |
| **Migration** | Migration scripts per-database, deploy độc lập |
| **Connection pooling** | Mỗi service connect đúng database của mình |
| **Access control** | PostgreSQL roles: `app_user` chỉ access `app_db`, `auth_user` chỉ access `auth_db` |
| **Monitoring** | Per-database metrics: connections, query latency, disk usage |
| **AWS mapping** | 1 RDS instance + multiple databases = cost-effective. Hoặc tách auth_db ra RDS riêng khi scale |

### Connection Strings

```bash
# Order, Payment, Inventory, Notification Workers
DATABASE_URL=postgresql://app_user:***@postgres:5432/app_db

# Auth Service
AUTH_DATABASE_URL=postgresql://auth_user:***@postgres:5432/auth_db

# Shipping Service + Worker
SHIPPING_DATABASE_URL=postgresql://shipping_user:***@postgres:5432/shipping_db
```

### So sánh với các approaches khác

| Approach | Services 6 | Services 10 | Services 30+ |
|----------|-----------|-------------|---------------|
| Shared DB (1 DB, all tables) | ✅ Đủ | ⚠️ Bắt đầu coupling | ❌ Nightmare |
| **Hybrid (1 instance, N DBs)** | ✅ | **✅ Sweet spot** | ⚠️ Cần tách instance |
| DB-per-instance | ❌ Overkill | ⚠️ Tốn resource | ✅ Cần thiết |

---

## Đề Xuất Mở Rộng (+4 Services)

### Tổng quan kiến trúc mới

```
                                    ┌──────────────┐
                                    │ Auth Service  │ (NEW)
                                    │   JWT/RBAC    │
                                    │  [auth_db]    │
                                    └──────┬───────┘
                                           │ verify token
                                           ▼
Web UI → API Gateway → Order Service → Payment Service
                │             ↕                ↕
                │        [app_db]            Redis
                │             ↕
                │          Kafka
                │        ↙   ↓    ↘
                │  Notif.  Inv.   Shipping Worker (NEW)
                │  Worker  Worker     ↕
                │                 Shipping Service (NEW)
                │                     ↕
                │                [shipping_db]
                │
                └──→ Search Service (NEW)
                         ↕
                     OpenSearch
                         ↑ sync
                     [app_db] (CDC/event)
```

---

### Service 1: Auth Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5006 |
| **Tech** | Python (Flask) + PyJWT |
| **Database** | PostgreSQL — `auth_db` (isolated) |
| **Mục đích** | Authentication + Authorization |

**Tại sao cần:**
- Hiện tại KHÔNG có authentication → tất cả APIs đều public
- Khi deploy AWS: cần hiểu JWT propagation qua nhiều services
- Production-grade: mọi service đều cần verify token

**Chức năng:**
```
POST /auth/register     → Tạo user, hash password (bcrypt)
POST /auth/login        → Return JWT (access + refresh token)
POST /auth/refresh      → Refresh access token
GET  /auth/verify       → Verify JWT (internal, cho các services khác gọi)
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| JWT local verification | API Gateway verify JWT locally bằng public key (không cần gọi HTTP tới Auth Service). Auth down = new login fail, nhưng existing sessions vẫn hoạt động |
| RBAC | User roles: `customer`, `admin`, `service` |
| Token refresh | Access token 15min, refresh token 7d |
| Service-to-service auth | Internal JWT với role `service` cho inter-service calls |
| Key rotation | JWT signing key rotation procedure — publish new public key trước, rotate private key sau |

**Schema bổ sung:**
```sql
CREATE TABLE users (
    id          SERIAL PRIMARY KEY,
    email       VARCHAR(255) UNIQUE NOT NULL,
    password    VARCHAR(255) NOT NULL,  -- bcrypt hash
    role        VARCHAR(50) DEFAULT 'customer',
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE refresh_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER REFERENCES users(id),
    token       VARCHAR(512) UNIQUE NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    revoked     BOOLEAN DEFAULT false
);
```

**Impact lên services hiện tại:**
- API Gateway: thêm middleware verify JWT
- Order Service: extract user_id từ JWT, gắn vào order
- Web UI: thêm login/register page, lưu token trong localStorage

---

### Service 2: Shipping Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5007 |
| **Tech** | Python (Flask) |
| **Database** | PostgreSQL — `shipping_db` (isolated) |
| **Mục đích** | Quản lý shipping sau khi payment thành công |

**Tại sao cần:**
- Hiện tại flow dừng ở Payment → không có gì xảy ra sau đó
- Production-grade: order → payment → **shipping** → delivery
- Tạo ra **Saga pattern** — distributed transaction thực tế

**Chức năng:**
```
POST /shipping/create        → Tạo shipment cho order
GET  /shipping/{order_id}    → Tracking status
POST /shipping/{id}/cancel   → Cancel shipment (compensation)
```

**Schema bổ sung:**
```sql
CREATE TABLE shipments (
    id              SERIAL PRIMARY KEY,
    order_id        VARCHAR(50) UNIQUE NOT NULL,
    status          VARCHAR(50) DEFAULT 'pending',
    -- pending → processing → shipped → delivered → cancelled
    carrier         VARCHAR(100),
    tracking_number VARCHAR(100),
    estimated_delivery TIMESTAMP,
    shipped_at      TIMESTAMP,
    delivered_at    TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW()
);
```

---

### Service 3: Shipping Worker (Saga Orchestrator)

| Attribute | Detail |
|-----------|--------|
| **Port** | 5008 |
| **Tech** | Python + Kafka consumer/producer |
| **Mục đích** | Orchestrate Saga: payment → shipping → notification |

**Tại sao cần:**
- Đây là service tạo ra **nhiều learning value nhất**
- Saga pattern = distributed transaction without 2PC
- Compensation logic khi bất kỳ step nào fail

**Flow:**
```
Saga: Order Fulfillment

Happy path:
  1. Order Service → publish order.created
  2. Payment Service → process → publish order.payment_completed
  3. Shipping Worker → consume → call Shipping Service → create shipment
  4. Shipping Worker → publish order.shipped
  5. Notification Worker → consume → notify customer "Your order has shipped"

Compensation (shipping fail):
  3. Shipping Worker → consume → call Shipping Service → FAIL (out of capacity)
  4. Shipping Worker → publish order.shipping_failed
  5. Shipping Worker → call Payment Service → refund
  6. Shipping Worker → publish order.refunded
  7. Notification Worker → consume → notify customer "Refund processed"
```

**Kafka topics bổ sung:**

| Topic | Producer | Consumer |
|-------|----------|----------|
| `order.shipped` | Shipping Worker | Notification Worker |
| `order.shipping_failed` | Shipping Worker | Notification Worker |
| `order.refunded` | Shipping Worker | Notification Worker, Inventory Worker |

**Saga State Machine:**
```
States: INITIATED → PAYMENT_PENDING → PAYMENT_COMPLETED → SHIPPING_PENDING
        → SHIPPED | SHIPPING_FAILED → COMPENSATING → REFUNDED | COMPENSATION_FAILED

Rules:
  - Timeout: 5 minutes per step, 15 minutes total saga
  - Retry: 3 attempts with exponential backoff (1s, 5s, 25s)
  - DLQ: after max_retries exhausted OR total timeout exceeded
  - Crash recovery: on startup, query saga_state for PENDING states → resume
```

**Schema bổ sung (shipping_db):**
```sql
CREATE TABLE saga_state (
    saga_id     VARCHAR(50) PRIMARY KEY,
    order_id    VARCHAR(50) NOT NULL,
    state       VARCHAR(50) NOT NULL,
    retries     INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    timeout_at  TIMESTAMP,
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **Saga Orchestration** | Coordinator quản lý multi-step transaction với persistent state |
| **Compensation** | Rollback khi downstream service fail |
| **Dead Letter Queue** | Messages xử lý fail → DLQ topic để review |
| **Retry with backoff** | Exponential backoff cho transient failures |
| **Crash recovery** | Resume incomplete sagas on restart từ saga_state table |

---

### Service 4: Search Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5009 |
| **Tech** | Python (Flask) + OpenSearch client |
| **Database** | OpenSearch (search index) |
| **Mục đích** | Full-text search cho products + orders |

**Tại sao cần:**
- Học data sync giữa PostgreSQL → OpenSearch (eventual consistency)
- Tạo CQRS pattern: write vào PostgreSQL, read từ OpenSearch
- Trên AWS: sử dụng Amazon OpenSearch Service

**Chức năng:**
```
GET  /search/products?q=laptop       → Full-text search products
GET  /search/orders?q=ORD-123        → Search orders by ID/status
POST /search/reindex                 → Manual reindex trigger
```

**Data sync approach (Event-driven):**
```
Sync strategy:
  1. Event-driven: listen order.created, order.updated → index to OpenSearch
  2. Backfill: POST /search/reindex → full scan app_db → bulk index
  3. Idempotency: use order_id as OpenSearch document _id (upsert, not insert)
  4. Failure handling: if OpenSearch write fails → publish to search.sync.dlq
  5. Index versioning: use aliases (orders_v1, orders_v2) for zero-downtime reindex
  6. Lag metric: track time giữa Kafka event timestamp và OpenSearch indexed_at
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **CQRS** | Separate read model (OpenSearch) vs write model (PostgreSQL) |
| **Eventual consistency** | Search index có thể lag 1-5s sau khi write, đo bằng metric |
| **Bulk indexing** | Batch sync cho reindex operations |
| **Index aliasing** | Zero-downtime reindex bằng alias switching |
| **Search relevance** | Scoring, boosting, fuzzy matching |

---

## Kiến Trúc Tổng Thể Sau Mở Rộng

### System Architecture (10 Services)

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                              Applications VM                                             │
│                                                                                          │
│  ┌─────────────────────────────────────── API Layer ──────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌──────────┐   rate    ┌──────────────┐    JWT     ┌─────────────────┐            │   │
│  │  │  Web UI  │──limit──►│ API Gateway  │──verify──►│  Auth Service   │            │   │
│  │  │  (nginx) │          │  Flask :5000  │◄──token───│  Flask :5006    │            │   │
│  │  │  :8580   │          │  + Circuit   │           │  [auth_db]      │            │   │
│  │  └──────────┘          │    Breaker    │           └─────────────────┘            │   │
│  │                        └──────┬───────┘                                           │   │
│  │                               │ HTTP                                              │   │
│  └───────────────────────────────┼───────────────────────────────────────────────────┘   │
│                                  ▼                                                       │
│  ┌─────────────────────────────── Core Services ─────────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌─────────────────┐  HTTP+CB  ┌──────────────┐        ┌──────────────────┐       │   │
│  │  │  Order Service  │─────────►│Payment Service│        │  Search Service  │       │   │
│  │  │  Flask :5001    │          │  Flask :5002   │        │  Flask :5009     │       │   │
│  │  │                 │          └──────────────┘        │  [OpenSearch]    │       │   │
│  │  │  [app_db]       │                                   └──────────────────┘       │   │
│  │  │  [Redis cache]  │                                          ▲                   │   │
│  │  └────────┬────────┘                                          │ event sync        │   │
│  │           │ Kafka produce                                     │                   │   │
│  └───────────┼───────────────────────────────────────────────────┼───────────────────┘   │
│              ▼                                                   │                       │
│  ┌─────────────────────────────── Event Bus ─────────────────────┼───────────────────┐   │
│  │                                                               │                   │   │
│  │  ┌─────────────────────────────────────┐                      │                   │   │
│  │  │           Kafka (KRaft :9092)        │                      │                   │   │
│  │  │                                     │                      │                   │   │
│  │  │  Topics:                            │                      │                   │   │
│  │  │   order.created ──────────────────────────────────────────►│                   │   │
│  │  │   order.payment_completed           │                                          │   │
│  │  │   order.payment_failed              │                                          │   │
│  │  │   order.shipped          (new)      │                                          │   │
│  │  │   order.shipping_failed  (new)      │                                          │   │
│  │  │   order.refunded         (new)      │                                          │   │
│  │  │   order.shipping.dlq     (new)      │                                          │   │
│  │  └──────────┬──────────────────────────┘                                          │   │
│  │             │ consume                                                             │   │
│  │     ┌───────┼───────────┬──────────────┐                                          │   │
│  │     ▼       ▼           ▼              │                                          │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐                           │   │
│  │  │  Notification │ │  Inventory   │ │ Shipping Worker  │ (NEW)                    │   │
│  │  │  Worker :5004 │ │  Worker :5005│ │  :5008           │                          │   │
│  │  │  [app_db]     │ │  [app_db]    │ │  Saga Orchestrator│                         │   │
│  │  └──────────────┘ └──────────────┘ │  + DLQ handler    │                          │   │
│  │                                     │  + Circuit Breaker│                          │   │
│  │                                     └────────┬─────────┘                          │   │
│  │                                              │ HTTP+CB                            │   │
│  │                                              ▼                                    │   │
│  │                                     ┌──────────────────┐                          │   │
│  │                                     │ Shipping Service │ (NEW)                    │   │
│  │                                     │  Flask :5007     │                          │   │
│  │                                     │  [shipping_db]   │                          │   │
│  │                                     └──────────────────┘                          │   │
│  └───────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│  ┌─────────────────────────────── Data Layer ────────────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌──────────────────────────┐  ┌──────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │      PostgreSQL :5432    │  │ Redis    │  │  OpenSearch  │  │  Kafka       │   │   │
│  │  │  ┌────────┬──────────┐  │  │  :6379   │  │   :9200      │  │  :9092       │   │   │
│  │  │  │ app_db │ auth_db  │  │  │  Cache   │  │  Search      │  │  KRaft mode  │   │   │
│  │  │  │        │          │  │  │  TTL 60s │  │  Index       │  │  8 topics    │   │   │
│  │  │  │        │shipping_ │  │  └──────────┘  └──────────────┘  │  + 1 DLQ     │   │   │
│  │  │  │        │db        │  │                                   └──────────────┘   │   │
│  │  │  └────────┴──────────┘  │                                                      │   │
│  │  └──────────────────────────┘                                                     │   │
│  │                                                                                    │   │
│  │  ┌──────────────┐  ┌──────────────┐                                               │   │
│  │  │ Kafka UI     │  │Kafka Exporter│                                               │   │
│  │  │  :8585       │  │  :9308       │                                               │   │
│  │  └──────────────┘  └──────────────┘                                               │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│  Resilience: Circuit Breaker (pybreaker) │ Rate Limit (Redis) │ Health Checks (/health)  │
│  Error Format: RFC 7807 + trace_id       │ Auth: JWT + RBAC   │ DLQ: order.shipping.dlq  │
└────────────────────────────────┬─────────────────────────────────────────────────────────┘
                                 │ OTLP (gRPC :4317)
┌────────────────────────────────▼─────────────────────────────────────────────────────────┐
│                          Observability VM                                                 │
│                                                                                          │
│  ┌────────────────┐  ┌────────────┐  ┌───────────────┐  ┌──────────────────────────┐    │
│  │ OTel Collector │─►│ Prometheus │─►│  Grafana      │  │  Dashboards:             │    │
│  │  :4317/:4318   │  │   :9090    │  │   :3000       │  │  • Application Health    │    │
│  │                │  └────────────┘  │               │  │  • Kafka Overview        │    │
│  │                │─►┌────────────┐  │               │  │  • Auth Overview    (NEW)│    │
│  │                │  │   Tempo    │  │               │  │  • Saga Monitor     (NEW)│    │
│  │                │  │   :3200    │  │               │  │  • Search Health    (NEW)│    │
│  │                │  └────────────┘  │               │  │  • Cross-Service    (NEW)│    │
│  │                │─►┌────────────┐  │               │  │  • SLI/SLO Burn Rate    │    │
│  │                │  │   Loki     │  └───────────────┘  └──────────────────────────┘    │
│  └────────────────┘  │   :3100    │  ┌───────────────┐                                  │
│                      └────────────┘  │ Alertmanager  │                                  │
│                                      │  → Telegram   │                                  │
│                                      │  Alerts:      │                                  │
│                                      │  • SLO burn   │                                  │
│                                      │  • Saga fail  │                                  │
│                                      │  • CB open    │                                  │
│                                      │  • Auth brute │                                  │
│                                      └───────────────┘                                  │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Ports Summary (Sau mở rộng)

| Port | Service | Type | Database |
|------|---------|------|----------|
| 5000 | API Gateway | HTTP + Rate Limit | - |
| 5001 | Order Service | HTTP | app_db + Redis |
| 5002 | Payment Service | HTTP | app_db |
| 5003 | Traffic Generator | HTTP | - |
| 5004 | Notification Worker | Kafka Consumer | app_db |
| 5005 | Inventory Worker | Kafka Consumer | app_db |
| **5006** | **Auth Service** (NEW) | HTTP | **auth_db** |
| **5007** | **Shipping Service** (NEW) | HTTP | **shipping_db** |
| **5008** | **Shipping Worker** (NEW) | Kafka Consumer + HTTP | **shipping_db** |
| **5009** | **Search Service** (NEW) | HTTP + Kafka Consumer | **OpenSearch** |
| 5432 | PostgreSQL | TCP | app_db, auth_db, shipping_db |
| 6379 | Redis | TCP | - |
| **9200** | **OpenSearch** (NEW) | HTTP | - |
| 8580 | Web UI | HTTP | - |
| 8585 | Kafka UI | HTTP | - |
| 9092 | Kafka | TCP | - |
| 9308 | Kafka Exporter | HTTP | - |

### Data Flow (Sau mở rộng)

```
Synchronous (HTTP + JWT + Circuit Breaker):
  Web UI → API Gateway ──JWT──► Auth Service (verify)
                       ──HTTP──► Order Service ──HTTP+CB──► Payment Service
                       ──HTTP──► Search Service ──query──► OpenSearch
                                 Shipping Worker ──HTTP+CB──► Shipping Service

Asynchronous (Kafka Event-Driven):
  Order Service ──publish──► Kafka
                                ├── order.created ──────► Notif Worker
                                │                  ──────► Inventory Worker
                                │                  ──────► Shipping Worker ──► Search Service
                                ├── order.payment_completed ► Notif + Shipping Worker
                                ├── order.payment_failed    ► Notif + Inventory
                                ├── order.shipped           ► Notif
                                ├── order.shipping_failed   ► Notif
                                ├── order.refunded          ► Notif + Inventory
                                └── order.shipping.dlq      ► Manual review
```

### Communication Matrix

```
                  API-GW  Order  Payment  Notif  Inv  Auth  Shipping  Ship-W  Search
API Gateway         -      HTTP    -        -     -    HTTP     -       -      HTTP
Order Service       -       -     HTTP      -     -    JWT      -       -       -
Payment Service     -       -      -        -     -    JWT      -       -       -
Notif Worker        -       -      -        -     -     -       -       -       -
Inventory Worker    -       -      -        -     -     -       -       -       -
Auth Service        -       -      -        -     -     -       -       -       -
Shipping Service    -       -      -        -     -    JWT       -       -       -
Shipping Worker     -       -     HTTP      -     -     -      HTTP     -       -
Search Service      -       -      -        -     -     -       -       -       -
```

### Kafka Topic Map

```
order.events (existing)
  ├── order.created           → Notif, Inventory, Shipping Worker
  ├── order.payment_completed → Notif, Shipping Worker
  └── order.payment_failed    → Notif, Inventory

order.shipping (new)
  ├── order.shipped           → Notif
  ├── order.shipping_failed   → Notif
  └── order.refunded          → Notif, Inventory

search.sync (new)
  ├── product.updated         → Search Service
  └── order.indexed           → Search Service
```

---

## Phân Tích Failure Scenarios Mới

Với 10 services, các failure scenarios phức tạp hơn đáng kể:

### Cascading Failures

| Scenario | Chain | Impact | Recovery |
|----------|-------|--------|----------|
| Auth Service down | Tất cả services từ chối request → toàn bộ hệ thống down | **Critical** — single point of failure | Circuit breaker: cache JWT verification 5 min |
| Shipping Service down | Payment thành công nhưng không ship được | Orders stuck ở `paid` status | Saga compensation → refund hoặc retry queue |
| OpenSearch down | Search không hoạt động, writes vẫn OK | **Degraded** — core flow không ảnh hưởng | Graceful degradation: fallback query PostgreSQL |
| Kafka down | Tất cả async flows dừng | **Critical** — orders create nhưng không process | Kafka cluster HA, consumer replay từ offset |

### New Chaos Exercises

| Exercise | Break | Observe | Recover |
|----------|-------|---------|---------|
| Kill Auth mid-request | Stop Auth container | Existing sessions còn hoạt động? New logins fail? | Restart + verify JWT cache |
| Kill Shipping during Saga | Stop Shipping Worker giữa chừng | Order stuck? Payment đã charge nhưng chưa ship? | Saga timeout → compensation → refund |
| OpenSearch index corrupt | Delete index | Search trả về 0 results | Reindex từ PostgreSQL |
| Kafka consumer lag | Slow down Shipping Worker (add 10s delay) | Queue backlog? Other consumers bị ảnh hưởng? | Scale consumer group hoặc fix bottleneck |

---

## Design Patterns Comparison

### Trước mở rộng (6 services)

```
Patterns:
  ✅ Sync HTTP (request-response)
  ✅ Async Pub/Sub (Kafka)
  ✅ Cache-Aside (Redis)
  ✅ BFF (API Gateway)
  ✅ Idempotent Processing
  ✅ Pessimistic Locking
  ✅ Trace Propagation (W3C)
```

### Sau mở rộng (10 services)

```
Tất cả patterns cũ +
  🆕 Saga Orchestration (distributed transactions + crash recovery)
  🆕 Compensation (rollback when downstream fails)
  🆕 Circuit Breaker (failure isolation + observability)
  🆕 CQRS (read/write model separation)
  🆕 Eventual Consistency (sync lag + measurement)
  🆕 Dead Letter Queue (failed message handling)
  🆕 JWT Local Verification (resilient auth)
  🆕 RBAC (role-based access control)
  🆕 Graceful Degradation (fallback khi dependency down)
  🆕 Retry with Exponential Backoff
  🆕 TLS Termination (HTTPS)
  🆕 Secrets Management (Docker secrets + .env)
  🆕 Network Segmentation (Docker networks per tier)
  🆕 Resource Limits (CPU/memory per container)
  🆕 Graceful Shutdown (SIGTERM handling)
  🆕 Backup/Restore (per-database + DR drill)
  🆕 Index Aliasing (zero-downtime reindex)
  🆕 CI Pipeline (lint + test + build)
```

---

## Resilience Patterns (Bổ sung cho tất cả services)

Ngoài 4 services mới, cần bổ sung các production-grade patterns cho **toàn bộ** services (cũ + mới):

### Health Check Endpoints

Mỗi service cần expose 2 endpoints chuẩn Kubernetes/ECS:

```
GET /health/live      → 200 nếu process đang chạy (liveness)
GET /health/ready     → 200 nếu service sẵn sàng nhận traffic (readiness)
```

| Service | Liveness | Readiness |
|---------|----------|----------|
| Order Service | Process alive | PostgreSQL connected + Redis connected + Kafka producer ready |
| Auth Service | Process alive | PostgreSQL connected (auth_db) |
| Shipping Worker | Process alive | Kafka consumer subscribed + PostgreSQL connected (shipping_db) |
| Search Service | Process alive | OpenSearch cluster health green/yellow |

**Tại sao quan trọng:**
- Docker Compose: `healthcheck` trong docker-compose.yml — container restart khi unhealthy
- AWS ECS: ALB target group health check → unhealthy task bị thay thế tự động
- Kubernetes: liveness/readiness probes → Pod restart hoặc tạm ngưng traffic

### Circuit Breaker

Áp dụng cho các HTTP calls giữa services:

```
API Gateway → Order Service:     circuit breaker (5 failures → open 30s)
Order Service → Payment Service: circuit breaker (3 failures → open 60s)
Shipping Worker → Shipping Svc:  circuit breaker (3 failures → open 60s)
```

**Implementation:** Dùng library `pybreaker` (Python) thay vì tự viết.

**Trạng thái:**
```
Closed    → requests đi bình thường, đếm failures
Open      → requests bị reject ngay, trả fallback response
Half-Open → cho 1 request thử, nếu OK → Close, nếu fail → Open lại
```

**Observability (bắt buộc):**
- Metric: `circuit_breaker_state{service="payment", state="open|closed|half_open"}` (Gauge)
- Metric: `circuit_breaker_failures_total{service="payment"}` (Counter)
- Alert: `CircuitBreakerOpen` — fires khi CB ở state "open" > 30s
- Log: structured log mỗi state transition với `trace_id`

### Rate Limiting

Áp dụng ở API Gateway (điểm vào duy nhất):

```
Global:     100 requests/second
Per-user:   20 requests/second (dựa trên JWT user_id)
Per-IP:     50 requests/second (cho unauthenticated endpoints)
```

**Implementation:** Redis-based sliding window counter.

**Observability:**
- Metric: `rate_limit_hits_total{tier="global|user|ip"}` (Counter)
- Internal bypass: requests với `X-Internal-Service` header + service JWT skip rate limit
- Response: 429 + RFC 7807 body + `Retry-After` header
- Alert: `RateLimitSpikeDetected` — rate_limit_hits > 100/min sustained 5min

### Structured Error Response (RFC 7807)

Tất cả services trả error theo chuẩn:

```json
{
  "type": "https://api.example.com/errors/insufficient-stock",
  "title": "Insufficient Stock",
  "status": 409,
  "detail": "Product 'Laptop' only has 2 in stock, requested 5",
  "instance": "/orders/ORD-20250512-001",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```

**Tại sao:** Khi có 10 services, error format không thống nhất → debug rất khó. `trace_id` trong error response giúp correlate với distributed traces.

### Graceful Shutdown (Kafka Consumers)

Tất cả Kafka consumers phải xử lý SIGTERM đúng:

```python
import signal, sys

def shutdown_handler(signum, frame):
    consumer.close()    # commits final offsets
    db_connection.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
```

```yaml
# docker-compose.yml
services:
  notification-worker:
    stop_grace_period: 30s   # thời gian chờ trước SIGKILL
```

**Tại sao:** Kill consumer mid-processing có thể gây duplicate processing hoặc saga state inconsistency.

### TLS Termination

HTTPS cho tất cả external traffic:

```
Client ──HTTPS──► nginx (TLS termination) ──HTTP──► API Gateway ──► services
```

- Self-signed certificates cho lab (openssl)
- nginx reverse proxy handle TLS
- Internal traffic giữa services vẫn HTTP (within Docker network)
- Certificate renewal procedure (scripted)

**DevOps learning:** TLS setup, certificate management, nginx SSL config, redirect HTTP→HTTPS.

### Secrets Management

Không hardcode secrets trong docker-compose.yml:

```yaml
# docker-compose.yml
services:
  order-service:
    env_file: .env.order   # file-based secrets, NOT inline
    secrets:
      - db_password
      - jwt_public_key

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_public_key:
    file: ./secrets/jwt_public.pem
```

- `.env.*` files trong `.gitignore`
- `secrets/` directory với restricted permissions (chmod 600)
- JWT key pair: private key chỉ Auth Service có, public key distribute cho các services
- Rotation procedure: generate new key → deploy public key → rotate private key

### Network Segmentation

Tách Docker networks theo tier:

```yaml
networks:
  frontend:    # Web UI, nginx
  backend:     # API Gateway, services
  data:        # PostgreSQL, Redis, Kafka, OpenSearch
  observability:  # OTel, Prometheus, Grafana (external)

services:
  web-ui:
    networks: [frontend]
  api-gateway:
    networks: [frontend, backend]   # bridge frontend → backend
  order-service:
    networks: [backend, data]       # access DB/cache
  postgres:
    networks: [data]                # chỉ data tier access được
```

**Tại sao:** Web UI không nên connect trực tiếp tới PostgreSQL. Network segmentation enforce tại infrastructure level.

### Resource Limits

```yaml
services:
  order-service:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
  opensearch:
    deploy:
      resources:
        limits:
          memory: 3G    # JVM heap + OS overhead
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
```

**Tại sao:** Without limits, 1 service có thể eat toàn bộ RAM của VM → OOM killer random containers.

### Backup & Restore

```bash
# Backup per-database
pg_dump -h localhost -U app_user app_db > backup/app_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U auth_user auth_db > backup/auth_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U shipping_user shipping_db > backup/shipping_db_$(date +%Y%m%d).sql

# Restore
pg_restore -h localhost -U app_user -d app_db < backup/app_db_20250519.sql

# Verify backup integrity
pg_restore --list backup/app_db_20250519.sql  # dry-run, no actual restore
```

- Backup schedule: daily (cron or Docker healthcheck trick)
- Retention: 7 days local, rotate oldest
- Verify: monthly restore drill to verify backups are usable
- **RTO/RPO definitions:** RTO = 30 min (restore from backup), RPO = 24h (daily backup)

### Log Rotation

```yaml
# docker-compose.yml — apply cho tất cả services
services:
  order-service:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

**Tại sao:** Without log rotation, Docker logs grow unbounded → disk full → entire VM down.

### CI Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  lint-test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint (flake8)
        run: flake8 applications-vm/applications/
      - name: Unit tests
        run: pytest applications-vm/applications/ --tb=short
      - name: Build images
        run: docker compose -f applications-vm/applications/docker-compose.yml build
      - name: Health check smoke test
        run: |
          docker compose up -d
          sleep 30
          curl -f http://localhost:5000/health/live
          docker compose down
```

- Deploy vẫn manual (`docker compose pull && up -d` trên VM)
- CI chỉ validate: code quality + build success + basic health
- Production deployment automation thuộc AWS plan (Terraform + ECS)

## Observability Mở Rộng

### Per-Service Metrics (mỗi service mới phải có)

| Metric type | Ví dụ | Instrument |
|------------|-------|------------|
| **Request rate** | `http_requests_total{service="auth",method="POST",path="/login"}` | Counter |
| **Latency** | `http_request_duration_seconds{service="shipping"}` | Histogram |
| **Error rate** | `http_requests_total{status="5xx",service="search"}` | Counter |
| **Business metric** | `saga_compensations_total{reason="shipping_failed"}` | Counter |
| **Queue lag** | `kafka_consumer_lag{group="shipping-worker"}` | Gauge |
| **Circuit breaker state** | `circuit_breaker_state{target="payment",state="open"}` | Gauge |
| **DB connections** | `db_pool_active_connections{database="auth_db"}` | Gauge |

### SLI/SLO Definitions

| Service | SLI | SLO Target |
|---------|-----|------------|
| API Gateway | Request success rate (non-5xx) | 99.5% over 7 days |
| Order Service | Order creation latency p99 | < 500ms |
| Auth Service | Login latency p99 | < 200ms |
| Shipping Worker | Saga completion rate | 99% (1% allowed compensations) |
| Search Service | Search latency p99 | < 300ms |
| Search Service | Index freshness (lag) | < 10 seconds |

### Grafana Dashboards Mới

| Dashboard | Panels |
|-----------|--------|
| **Auth Overview** | Login rate, token refresh rate, failed logins (brute force?), active sessions |
| **Saga Monitor** | Saga in-flight, completion rate, compensation rate, DLQ size |
| **Search Health** | Index lag, query latency, OpenSearch cluster health |
| **Cross-Service** | Service dependency map, error propagation, trace duration distribution |

---

## Phân Phase Triển Khai

### Phase 0: Production Readiness (trước khi thêm services)

```
Effort: ~3-4 ngày
Dependencies: Không có
Impact: Tất cả 6 services hiện tại

Application:
  1. Thêm /health/live + /health/ready cho 6 services hiện tại
  2. Thêm healthcheck trong docker-compose.yml
  3. Chuẩn hóa error response format (RFC 7807)
  4. Chuẩn hóa logging format (đã có structured JSON, verify consistency)
  5. Thêm graceful shutdown handler cho Kafka consumers (SIGTERM)

Infrastructure:
  6. Network segmentation: tách Docker networks (frontend, backend, data, observability)
  7. Resource limits: CPU/memory limits cho tất cả containers
  8. Log rotation: json-file driver với max-size/max-file
  9. stop_grace_period: 30s cho tất cả workers

CI:
  10. Setup GitHub Actions: lint (flake8) → build → smoke test

Verify:
  - curl /health/ready → 200 khi service healthy
  - Stop PostgreSQL → /health/ready → 503
  - Error responses đúng format RFC 7807
  - Web UI không connect được trực tiếp tới PostgreSQL (network segmentation)
  - docker stats hiển thị memory limits
  - docker compose down: consumers commit offsets trước khi exit
  - CI pipeline pass trên GitHub
```

### Phase 1: Auth Service + TLS + Secrets

```
Effort: ~4-5 ngày
Dependencies: Phase 0 (health checks, network segmentation)
Impact: Tất cả services cần update middleware

Application:
  1. Tạo auth_db + init-auth.sql (users, refresh_tokens tables)
  2. Tạo Auth Service (register, login, verify, refresh)
  3. Update API Gateway — thêm JWT middleware (local public key verification) + rate limiting
  4. Update Order Service — extract user_id từ token
  5. Update Web UI — thêm login/register page

Infrastructure:
  6. TLS termination: self-signed cert + nginx SSL config
  7. Secrets management: JWT key pair, DB passwords trong .env files + Docker secrets
  8. HTTP → HTTPS redirect

Observability:
  9. Thêm Grafana dashboard: Auth Overview
  10. Alert: AuthBruteForceDetected (failed logins > 10/min)

Runbook deliverables:
  - RB-AUTH-01: Auth Service Down (new logins fail, existing sessions OK)
  - RB-AUTH-02: Brute Force Detected (rate limit spike on /auth/login)
  - RB-AUTH-03: JWT Key Rotation procedure
  - RB-TLS-01: Certificate Expired / Renewal

Verify:
  - Unauthenticated request → 401
  - Authenticated request → flow bình thường
  - Expired token → 401, refresh → new token
  - Rate limit exceeded → 429 Too Many Requests
  - Auth Service down → existing JWT vẫn valid (local verification)
  - HTTPS works, HTTP redirects to HTTPS
  - Secrets không hiện trong docker-compose.yml hoặc git
```

### Phase 2: Shipping Service + Shipping Worker + Backup

```
Effort: ~5-7 ngày
Dependencies: Phase 1 (Auth) nếu muốn auth, hoặc độc lập
Impact: Mở rộng order lifecycle, thêm Kafka topics

Application:
  1. Tạo shipping_db + init-shipping.sql (shipments + saga_state tables)
  2. Tạo Shipping Service (CRUD shipments) + circuit breaker
  3. Tạo Shipping Worker (Saga orchestrator) + DLQ handling + crash recovery
  4. Thêm Kafka topics: order.shipped, order.shipping_failed, order.refunded
  5. Thêm DLQ topic: order.shipping.dlq
  6. Update Notification Worker — handle shipping events
  7. Update Inventory Worker — handle refund events
  8. Update Web UI — hiển thị shipping status + tracking

Infrastructure:
  9. Backup/Restore: setup pg_dump scripts cho app_db, auth_db, shipping_db
  10. Horizontal scaling test: chạy 2 instances Shipping Worker (consumer group rebalancing)
  11. Backup verification: restore backup to temp DB, verify data integrity

Observability:
  12. Thêm Grafana dashboard: Saga Monitor
  13. Alert: SagaStuckInPending, DLQGrowing, CircuitBreakerOpen

Runbook deliverables:
  - RB-SAGA-01: Saga Stuck in PENDING (timeout not triggered)
  - RB-SAGA-02: DLQ Growing (compensation failures accumulating)
  - RB-SAGA-03: Shipping Service Down (CB open, sagas queuing)
  - RB-BACKUP-01: Database Restore Procedure (per-database)

Verify:
  - Order → Payment OK → Shipping OK → status: shipped
  - Order → Payment OK → Shipping FAIL → refund → status: refunded
  - Kill Shipping Worker mid-saga → resume after restart (saga_state)
  - Saga timeout → DLQ → manual review
  - Circuit breaker open → Shipping Worker stops calling Shipping Service
  - 2 Shipping Workers → Kafka rebalance, no duplicate processing
  - Backup restore drill: dump → drop → restore → verify data
```

### Phase 3: Search Service + Index Management

```
Effort: ~3-4 ngày
Dependencies: Không có — standalone service
Impact: Thêm OpenSearch container, data sync

Application:
  1. Thêm OpenSearch container vào docker-compose (+ healthcheck + resource limits 3GB)
  2. Tạo Search Service (search API + event-driven indexing)
  3. Implement idempotent sync (order_id as document _id, upsert)
  4. Implement backfill: POST /search/reindex → full scan app_db
  5. Implement index aliasing (orders_v1, orders_v2) for zero-downtime reindex
  6. Update API Gateway — route /search/* (circuit breaker)
  7. Update Web UI — thêm search bar

Infrastructure:
  8. OpenSearch snapshot/backup configuration
  9. Index lifecycle policy (delete old indices after 30 days)
  10. Failure handling: search.sync.dlq cho failed indexing

Observability:
  11. Thêm Grafana dashboard: Search Health (index lag, query latency)
  12. Metric: search_index_lag_seconds (event timestamp vs indexed_at)
  13. Alert: SearchIndexLagHigh (lag > 30s)

Runbook deliverables:
  - RB-SEARCH-01: OpenSearch Cluster Red (all replicas lost)
  - RB-SEARCH-02: Index Corruption → Reindex from PostgreSQL
  - RB-SEARCH-03: Search Index Lag High (sync falling behind)

Verify:
  - Search trả kết quả đúng
  - Tạo order mới → search thấy sau ≤ 5s (measure actual lag)
  - OpenSearch down → graceful error, core flow không ảnh hưởng
  - Reindex command → full sync hoàn tất
  - Zero-downtime reindex: alias switch với no search disruption
```

### Phase 4: Advanced Observability & Reliability Engineering
```
Effort: ~5-7 ngày
Dependencies: Phase 1-3 hoàn tất (Toàn bộ 10 services đã chạy ổn định)
Impact: Toàn bộ pipeline Observability, thay đổi cách định nghĩa reliability và debug

Mục tiêu:
Chuyển dịch observability từ "reactive monitoring" (đợi alert mới biết lỗi) sang "proactive reliability engineering" (đo lường business impact, proactive synthetic testing, và debug distributed transactions end-to-end).

5 Trụ cột triển khai:
  A. Saga Distributed Tracing
  B. SLO & MWMBR Alerting cho services mới
  C. Synthetic Monitoring (User-Centric SLIs)
  D. Multi-ID Log Correlation
  E. Business Metrics Instrumentation

A. Saga Distributed Tracing (Gắn với Phase 2)
Application:
  1. Instrument Saga Worker để inject `saga_id` và `saga_state` vào OTel span attributes.
  2. Cấu hình Kafka Producer/Consumer inject và extract `saga_id` qua Kafka message headers (bên cạnh W3C `traceparent` chuẩn).
  3. Enrich structured logs của tất cả workers với `saga_id` để đồng bộ qua 3 pillars.

Infrastructure:
  4. Update OTel Collector config: Thêm `saga.id` vào whitelist của spanmetrics connector và tail-sampling policies (luôn giữ lại 100% traces có `saga.state=COMPENSATING`).

Observability:
  5. Grafana Dashboard "Saga Monitor":
     - Panel: Saga Duration Distribution (Histogram).
     - Panel: Saga State Machine Flow (Node Graph plugin).
     - Panel: DLQ Size & Compensation Failure Rate.
  6. Tempo TraceQL Queries: Lưu các query mẫu để tìm traces theo `saga.id` hoặc filter các sagas bị timeout.
  7. Recording Rules & Alerts:
     - Alert: `SagaHighFailureRate` (Tỷ lệ compensation > 5% trong 5 phút).
     - Alert: `SagaDLQGrowing` (Messages trong DLQ topic > 10).

B. SLO & MWMBR Alerting cho Services Mới
Application:
  1. Định nghĩa SLIs cho các services mới:
     - Auth Service: Login latency P99 < 200ms (Target 99.5%).
     - Shipping Service: Shipment creation success rate (Target 99.5%).
     - Search Service: Query latency P95 < 300ms & Index lag < 10s (Target 95%).

Infrastructure:
  2. Prometheus Recording Rules: Tạo các SLI recording rules theo chuẩn naming convention `sli:<service>_<signal>:<window>` (5m, 30m, 1h, 6h).

Observability:
  3. Grafana SLO Dashboard: Mở rộng dashboard hiện tại, thêm các gauges và burn-rate charts cho Auth, Shipping, Search.
  4. MWMBR Alerts (Multi-Window Multi-Burn-Rate):
     - Cấu hình Fast-burn (14.4x) và Slow-burn (3x) alerts cho các SLOs mới.
     - Áp dụng Traffic Guards (dựa trên span metrics) để tránh phantom alerts khi không có traffic.

C. Synthetic Monitoring (User-Centric SLIs)
Infrastructure:
  1. Đóng gói Playwright E2E tests thành một Docker container headless Chrome.
  2. Triển khai container này trong Docker Compose, cấu hình chạy định kỳ (Cron / Systemd timer) mỗi 5 phút.
  3. Deploy một lightweight metrics exporter (Python/Node) để parse JSON results từ Playwright và push metrics (journey duration, success rate) về Prometheus Pushgateway.

Observability:
  4. Grafana Dashboard "Synthetic Journeys": Hiển thị Success Rate và P95 Duration của các luồng "Critical Purchase" và "Search" từ góc độ người dùng thực tế (outside-in).
  5. Alert: `SyntheticJourneyFailing` (Báo động khi luồng E2E lõi fail 2 lần liên tiếp, bất kể server-side metrics có đang xanh hay không).

D. Multi-ID Log Correlation
Application:
  1. Chuẩn hóa logging context: Đảm bảo mọi services đều enrich logs với `user_id`, `session_id`, `order_id` (bên cạnh `trace_id`, `span_id` mặc định của OTel).

Infrastructure:
  2. Grafana Alloy / Loki Pipeline: Cấu hình pipeline extract các correlation IDs này từ JSON logs (nhưng KHÔNG đưa vào Loki labels để tránh cardinality explosion, chỉ dùng cho LogQL line filters).
  3. Grafana Datasource Config (Derived Fields):
     - Cấu hình regex để biến `saga_id`, `user_id`, `order_id` trong Log panel thành các hyperlink.
     - Click vào `trace_id` -> Jump to Tempo.
     - Click vào `order_id` -> Jump to Business KPI dashboard với filter sẵn.

E. Business Metrics Instrumentation
Application:
  1. Instrument OTel Custom Metrics gắn liền với business KPIs:
     - Order Service: `revenue_dollars` (Histogram).
     - Payment Service: `payment_success_total` (Counter, group by provider).
     - Search Service: `search_to_purchase_total` (Counter, track qua session_id).
     - API Gateway: `cart_additions_total` vs `cart_checkouts_total`.

Observability:
  2. Grafana Dashboard "Business KPIs":
     - Panel: Real-time Revenue per Hour.
     - Panel: Payment Success Rate by Provider (Stripe vs PayPal).
     - Panel: Cart Abandonment Rate.
     - Panel: Search Conversion Funnel.
  3. Business Alerts (Optional): `RevenueDropped`, `HighCartAbandonment`, `PaymentProviderDegraded`.

Runbook Deliverables:
  - RB-SAGA-04: Saga High Failure Rate & DLQ Overflow.
  - RB-SLO-NEW: SLO Violation cho Auth, Shipping, Search.
  - RB-SYNTHETIC-01: Synthetic Journey Failing (Outside-in troubleshooting).
  - RB-CORRELATION-01: Debug User-Specific & Saga Issues (Multi-ID tracing).
  - RB-BUSINESS-01: Payment Provider Degraded & Revenue Drop.

Verify:
  - Trace một Saga từ Order -> Payment -> Shipping trên Tempo, thấy full chain `saga_id` và state transitions.
  - Inject latency vào Auth Service -> AuthLoginLatencyFastBurn alert fires trong < 2 phút.
  - Stop Payment Service -> Synthetic Journey alert fires (dù server-side health checks vẫn có thể pass).
  - Query Loki bằng `{user_id="user-123"} | saga_id!=""` để cross-correlate user actions với backend sagas.
  - Dashboard Business KPIs cập nhật real-time revenue và cart abandonment rate khi chạy Traffic Generator.
```

### Phase 5: Integration + Chaos Testing + SLO + DR Drill

```
Effort: ~5-7 ngày
Dependencies: Phase 0-3 hoàn tất

Integration:
  1. End-to-end test toàn bộ 10 services
  2. Thiết lập SLI/SLO dashboards trong Grafana
  3. Thêm alerting rules:
     - Saga failure rate > 5% → alert
     - Auth error rate > 1% → alert (brute force?)
     - Search index lag > 30s → alert
     - Circuit breaker open → alert

Chaos Exercises:
  4. Kill Auth → observe existing sessions still work (local JWT) → new logins fail
  5. Kill Shipping mid-saga → verify crash recovery from saga_state
  6. Corrupt OpenSearch index → verify graceful degradation + reindex
  7. Kafka consumer lag → verify backpressure + scaling
  8. PostgreSQL stop + restart → verify reconnection + health check transition
  9. Fill disk to 95% → verify predict_linear alert fires

Disaster Recovery Drill:
  10. Full DR: dump all DBs → docker compose down → remove volumes → restore → verify
  11. Document RTO (target: 30 min) và RPO (target: 24h) thực tế
  12. On-call simulation: trigger random alert, triage theo runbook, đo MTTR

Documentation:
  13. Update INCIDENT_RUNBOOK.md với runbooks từ Phase 1-3
  14. Document SLO burn rate qua 1 tuần vận hành
  15. Write post-mortem template cho mỗi chaos exercise

Verify:
  - Tất cả traces span đúng 10 services
  - SLO dashboards hiển thị burn rate
  - Mỗi chaos exercise có documented recovery < 5 phút
  - Alert → Telegram notification trong < 1 phút
  - DR drill: full restore hoàn tất < 30 phút
  - CI pipeline pass với 10 services
```

### Phase 6: Reliability & Automated Testing Strategy

```
Effort: ~5-7 ngày
Dependencies: Phase 4 (Integration & Chaos) hoàn tất
Impact: Toàn bộ CI/CD pipeline, thay đổi cách merge code và deploy

Mục tiêu:
Chuyển dịch từ "Manual Testing & Chaos" (Phase 4) sang "Automated Reliability Gates". 
Đảm bảo mọi thay đổi code đều được validate tự động về: Performance (SLO), API Contracts (Anti-breakage), và User Journeys (E2E) trước khi merge.

Testing Pillars & Tooling Strategy
| Pillar
|Tool
|Mục đích (SRE/Platform Lens)
|Integration Point
|
| ---|---|---|---|
| Performance & SLO
|k6
|Validate P99 latency & throughput không vi phạm SLO khi có code mới.
|CI Pipeline, export metrics to Prometheus
|
| API Contract
|Pact
|Ngăn chặn breaking changes giữa 10 services (Consumer-Driven Contracts).
|Pact Broker container, CI pre-merge gate
|
| Synthetic / E2E
|Playwright
|Đo lường SLI từ góc độ người dùng (User Journey) thay vì chỉ server-side metrics.
|Scheduled container (Cron), push metrics to Pushgateway
|

Architecture & Integration
1. k6 Load Testing (Performance Baseline):
   - Chạy script `baseline.js` trong CI sau khi build Docker image thành công.
   - k6 output trực tiếp vào Prometheus (qua remote_write hoặc OTel Collector).
   - CI Gate: Auto-fail PR nếu `p99 latency > SLO threshold` hoặc `error rate > 0.5%`.

2. Pact Contract Testing (API Governance):
   - Deploy `pact-broker` (Ruby/PostgreSQL) làm service phụ trợ trong Docker Compose (hoặc CI container).
   - Các service đóng vai trò Consumer (VD: Shipping Worker) publish expectations.
   - Các service đóng vai trò Provider (VD: Order Service) verify contracts trước khi cho phép merge.
   - Ngăn chặn lỗi: Order Service đổi tên field `order_id` -> `orderId` làm Shipping Worker crash.

3. Playwright Synthetic Monitoring (User-Centric SLI):
   - Đóng gói Playwright tests thành một Docker container headless Chrome.
   - Chạy định kỳ (mỗi 5 phút) trên Observability VM hoặc CI nightly.
   - Đo thời gian hoàn thành luồng "Login -> Create Order -> View Events".
   - Push duration metrics về Prometheus để hiển thị trên Grafana SLO Dashboard.

Deliverables (Cấu trúc thư mục mới)
observability-lab/
+-- tests/
    +-- load/                  # k6 scripts & thresholds
       +-- baseline.js
       +-- stress.js
    +-- contracts/             # Pact consumer/provider tests
       +-- broker/            # Docker compose cho Pact Broker
       +-- consumers/
       +-- providers/
    +-- e2e/                   # Playwright synthetic journeys
        +-- journeys/
        +-- Dockerfile         # Headless chrome container

Observability (Mở rộng Grafana):
- Dashboard: "CI/CD Reliability Gates" (Hiển thị lịch sử P99 latency qua các lần chạy k6).
- Dashboard: "Synthetic User Journeys" (Success rate & duration của Playwright tests).
- Alert: `SyntheticJourneyFailing` (Báo động khi luồng E2E lõi bị lỗi, bất kể server metrics có đang xanh hay không).

Verify:
- Tạo một PR cố tình làm thay đổi HTTP Status Code của Order Service -> CI block merge do Pact Contract fail.
- Tạo một PR cố tình thêm `time.sleep(2)` vào Payment Service -> CI block merge do k6 P99 vượt SLO.
- Dashboard Synthetic hiển thị được thời gian thực của luồng "Create Order" từ góc độ browser.
- Toàn bộ tests chạy headless và tự động cleanup sau khi CI chạy xong.
```
---

## Chi Phí Ảnh Hưởng

### Docker Compose (On-Premises)

| Resource | Hiện tại (6 svc) | Sau mở rộng (10 svc) | Delta |
|----------|-----------------|---------------------|-------|
| RAM | ~2.5 GB | ~7 GB (+OpenSearch ~3 GB) | +4.5 GB |
| CPU | 2-4 cores đủ | 6-8 cores khuyến nghị | +4 cores |
| Disk | ~1 GB | ~5 GB (OpenSearch indices + backups) | +4 GB |

### AWS (ước tính khi deploy)

| Resource | Hiện tại | Sau mở rộng | Delta |
|----------|---------|-------------|-------|
| ECS Tasks | 6 tasks | 10 tasks | +~$20/mo |
| OpenSearch | - | t3.small.search | +~$25/mo |
| Kafka topics | 3 | 8 | +~$5/mo |
| **Total delta** | | | **+~$50/mo** |

---

## Tổng Kết

| Metric | Trước | Sau |
|--------|-------|-----|
| Services | 6 | 10 |
| Kafka topics | 3 | 8 + 1 DLQ |
| Design patterns | 7 | 25+ |
| Failure scenarios | ~5 | ~15 |
| Resilience patterns | 0 | 5 (CB, rate limit, health checks, graceful shutdown, graceful degradation) |
| Security | 0 | 3 (TLS, secrets management, JWT/RBAC) |
| Communication patterns | 2 (HTTP, Kafka) | 3 (+JWT propagation) |
| Database systems | 2 (PostgreSQL, Redis) | 3 (+OpenSearch) |
| Databases | 1 (shared) | 3 (app_db, auth_db, shipping_db) + OpenSearch |
| DB strategy | Shared DB | Hybrid (1 instance, multiple DBs) |
| Infrastructure ops | Basic | Network segmentation, resource limits, log rotation, backup/restore |
| CI/CD | None | GitHub Actions (lint → test → build) |
| Observability | Metrics + Logs + Traces | + SLI/SLO dashboards + per-service metrics + CB/rate limit metrics |
| Grafana dashboards | Existing | +4 (Auth, Saga, Search, Cross-Service) |
| Runbooks | 0 per new service | 10+ (per-phase deliverables) |
| Effort | - | ~20-27 ngày (5 phases) |

> **Kết luận:** Mở rộng 4 services + production-grade operational patterns sẽ tăng learning surface gấp ~4x so với hiện tại. Docker Compose được sử dụng như **production orchestrator** (không phải toy/demo) — tất cả concepts (TLS, secrets, network segmentation, backup, CI, graceful shutdown) đều production-grade, chỉ khác K8s ở deployment tooling. AWS deployment với Terraform/EKS/ECS là plan riêng.
