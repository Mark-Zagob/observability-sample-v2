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
| JWT propagation | API Gateway forward JWT → Order Service verify → Payment Service verify |
| RBAC | User roles: `customer`, `admin`, `service` |
| Token refresh | Access token 15min, refresh token 7d |
| Service-to-service auth | Internal JWT với role `service` cho inter-service calls |

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

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **Saga Orchestration** | Coordinator quản lý multi-step transaction |
| **Compensation** | Rollback khi downstream service fail |
| **Dead Letter Queue** | Messages xử lý fail → DLQ topic để review |
| **Retry with backoff** | Exponential backoff cho transient failures |

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

**Data sync approach:**
```
Option A: Event-driven sync (recommended)
  Order Service → publish order.created → Search Worker → index vào OpenSearch
  
Option B: CDC (Change Data Capture)
  PostgreSQL → WAL → Debezium → Kafka → Search Worker → OpenSearch
  (phức tạp hơn, nhưng production-grade hơn)
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **CQRS** | Separate read model (OpenSearch) vs write model (PostgreSQL) |
| **Eventual consistency** | Search index có thể lag 1-5s sau khi write |
| **Bulk indexing** | Batch sync cho reindex operations |
| **Search relevance** | Scoring, boosting, fuzzy matching |

---

## Kiến Trúc Tổng Thể Sau Mở Rộng

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
  🆕 Saga Orchestration (distributed transactions)
  🆕 Compensation (rollback when downstream fails)
  🆕 Circuit Breaker (failure isolation)
  🆕 CQRS (read/write model separation)
  🆕 Eventual Consistency (sync lag)
  🆕 Dead Letter Queue (failed message handling)
  🆕 JWT Propagation (cross-service auth)
  🆕 RBAC (role-based access control)
  🆕 Graceful Degradation (fallback khi dependency down)
  🆕 Retry with Exponential Backoff
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
Closed  → requests đi bình thường, đếm failures
Open    → requests bị reject ngay, trả fallback response
Half-Open → cho 1 request thử, nếu OK → Close, nếu fail → Open lại
```

### Rate Limiting

Áp dụng ở API Gateway (điểm vào duy nhất):

```
Global:     100 requests/second
Per-user:   20 requests/second (dựa trên JWT user_id)
Per-IP:     50 requests/second (cho unauthenticated endpoints)
```

**Implementation:** Redis-based sliding window counter.

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

---

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
Effort: ~1-2 ngày
Dependencies: Không có
Impact: Tất cả 6 services hiện tại

Bước:
  1. Thêm /health/live + /health/ready cho 6 services hiện tại
  2. Thêm healthcheck trong docker-compose.yml
  3. Chuẩn hóa error response format (RFC 7807)
  4. Chuẩn hóa logging format (đã có structured JSON, verify consistency)

Verify:
  - curl /health/ready → 200 khi service healthy
  - Stop PostgreSQL → /health/ready → 503
  - Error responses đúng format RFC 7807
```

### Phase 1: Auth Service

```
Effort: ~2-3 ngày
Dependencies: Phase 0 (health checks)
Impact: Tất cả services cần update middleware

Bước:
  1. Tạo auth_db + init-auth.sql (users, refresh_tokens tables)
  2. Tạo Auth Service (register, login, verify, refresh)
  3. Update API Gateway — thêm JWT middleware + rate limiting
  4. Update Order Service — extract user_id từ token
  5. Update Web UI — thêm login/register page
  6. Thêm Grafana dashboard: Auth Overview
  7. Test: end-to-end flow với authentication

Verify:
  - Unauthenticated request → 401
  - Authenticated request → flow bình thường
  - Expired token → 401, refresh → new token
  - Rate limit exceeded → 429 Too Many Requests
  - Auth Service down → circuit breaker → 503 Service Unavailable
```

### Phase 2: Shipping Service + Shipping Worker

```
Effort: ~3-5 ngày
Dependencies: Phase 1 (Auth) nếu muốn auth, hoặc độc lập
Impact: Mở rộng order lifecycle, thêm Kafka topics

Bước:
  1. Tạo shipping_db + init-shipping.sql (shipments table)
  2. Tạo Shipping Service (CRUD shipments) + circuit breaker
  3. Tạo Shipping Worker (Saga orchestrator) + DLQ handling
  4. Thêm Kafka topics: order.shipped, order.shipping_failed, order.refunded
  5. Thêm DLQ topic: order.shipping.dlq
  6. Update Notification Worker — handle shipping events
  7. Update Inventory Worker — handle refund events
  8. Update Web UI — hiển thị shipping status + tracking
  9. Thêm Grafana dashboard: Saga Monitor
  10. Test: happy path + compensation path

Verify:
  - Order → Payment OK → Shipping OK → status: shipped
  - Order → Payment OK → Shipping FAIL → refund → status: refunded
  - Kill Shipping Worker mid-saga → resume after restart
  - Saga timeout → DLQ → manual review
  - Circuit breaker open → Shipping Worker stops calling Shipping Service
```

### Phase 3: Search Service

```
Effort: ~2-3 ngày
Dependencies: Không có — standalone service
Impact: Thêm OpenSearch container, data sync

Bước:
  1. Thêm OpenSearch container vào docker-compose (+ healthcheck)
  2. Tạo Search Service (search API + indexing)
  3. Tạo sync mechanism (event-driven: listen order.created → index)
  4. Update API Gateway — route /search/* (circuit breaker)
  5. Update Web UI — thêm search bar
  6. Thêm Grafana dashboard: Search Health (index lag, query latency)
  7. Test: create order → search tìm thấy (eventual consistency)

Verify:
  - Search trả kết quả đúng
  - Tạo order mới → search thấy sau ≤ 5s (measure actual lag)
  - OpenSearch down → graceful error, core flow không ảnh hưởng
  - Reindex command → full sync hoàn tất
```

### Phase 4: Integration + Chaos Testing + SLO

```
Effort: ~3-5 ngày
Dependencies: Phase 0-3 hoàn tất

Bước:
  1. End-to-end test toàn bộ 10 services
  2. Thiết lập SLI/SLO dashboards trong Grafana
  3. Thêm alerting rules:
     - Saga failure rate > 5% → alert
     - Auth error rate > 1% → alert (brute force?)
     - Search index lag > 30s → alert
     - Circuit breaker open → alert
  4. Chạy chaos exercises:
     a. Kill Auth → observe cascade → verify circuit breaker
     b. Kill Shipping mid-saga → verify compensation
     c. Corrupt OpenSearch index → verify graceful degradation
     d. Kafka consumer lag → verify backpressure
     e. PostgreSQL failover (stop + restart) → verify reconnection
  5. Viết runbook recovery cho mỗi scenario
  6. Document SLO burn rate qua 1 tuần vận hành

Verify:
  - Tất cả traces span đúng 10 services
  - SLO dashboards hiển thị burn rate
  - Mỗi chaos exercise có documented recovery < 5 phút
  - Alert → Telegram notification trong < 1 phút
```

---

## Chi Phí Ảnh Hưởng

### Docker Compose (On-Premises)

| Resource | Hiện tại (6 svc) | Sau mở rộng (10 svc) | Delta |
|----------|-----------------|---------------------|-------|
| RAM | ~2.5 GB | ~4.5 GB (+OpenSearch ~1.5 GB) | +2 GB |
| CPU | 2-4 cores đủ | 4-6 cores khuyến nghị | +2 cores |
| Disk | ~1 GB | ~3 GB (OpenSearch indices) | +2 GB |

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
| Design patterns | 7 | 20 |
| Failure scenarios | ~5 | ~15 |
| Resilience patterns | 0 | 3 (circuit breaker, rate limit, health checks) |
| Communication patterns | 2 (HTTP, Kafka) | 3 (+JWT propagation) |
| Database systems | 2 (PostgreSQL, Redis) | 3 (+OpenSearch) |
| Databases | 1 (shared) | 3 (app_db, auth_db, shipping_db) + OpenSearch |
| DB strategy | Shared DB | Hybrid (1 instance, multiple DBs) |
| Observability | Metrics + Logs + Traces | + SLI/SLO dashboards + per-service metrics |
| Grafana dashboards | Existing | +3 (Auth, Saga, Search) |

> **Kết luận:** Mở rộng 4 services + resilience patterns + SLI/SLO sẽ tăng learning surface gấp ~3x so với hiện tại. Đặc biệt Phase 0 (production readiness) và Phase 4 (SLO + chaos) là nơi học được nhiều kiến thức SRE nhất — không phải từ code mà từ **cách vận hành và đo lường reliability**.
