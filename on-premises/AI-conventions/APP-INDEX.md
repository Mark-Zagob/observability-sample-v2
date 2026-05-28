# APP-INDEX.md — Application Conventions

> **Mục đích:** Quy tắc đặt tên, conventions, patterns cho application layer (services, Kafka, errors, logging, tracing, health checks).
>
> **Khi nào dùng:** Khi user hỏi về code task — tạo service mới, add metric, viết Kafka consumer, handle error, v.v.
>
> **Cập nhật:** 2026-05-28

---

## 📋 QUICK ROUTING

| Task | Xem section |
|------|-------------|
| Tạo service mới | §1 Service Naming + §9 Checklist |
| Add custom metric | §2 Metric Naming + §3 OTel SDK |
| Log một event | §4 Logging Standards |
| Wrap operation trong span | §5 Tracing Standards |
| Return error response | §6 Error Handling (RFC 7807) |
| Add health check | §7 Health Check Endpoints |
| Produce/consume Kafka | §8 Kafka Conventions |
| Add resilience pattern | §10 Future Patterns (CB, Saga, Rate Limit) |

---

## 1️⃣ SERVICE NAMING

**Pattern:** kebab-case (lowercase + dấu gạch ngang)

✅ Đúng:
- `order-service`, `payment-service`, `inventory-worker`
- `api-gateway`, `traffic-gen`, `notification-worker`

❌ Sai:
- `OrderService` (PascalCase)
- `payment_service` (snake_case)
- `inventoryworker` (no separator)

**Quy tắc phân biệt `service` vs `worker`:**

- `*-service`: HTTP server, nhận requests trực tiếp
- `*-worker`: Kafka consumer, xử lý async events

---

## 2️⃣ METRIC NAMING

**Pattern:** `{namespace}_{subsystem}_{name}_{unit}` — snake_case

### Unit suffixes chuẩn

| Suffix | Meaning | Type |
|--------|---------|------|
| `_total` | Counter (tích lũy, chỉ tăng) | Counter |
| `_seconds` | Duration | Histogram |
| `_bytes` | Size | Histogram/Gauge |
| `_ratio` | Tỉ lệ 0-1 | Gauge |
| `_percent` | Tỉ lệ 0-100 | Gauge |

### Ví dụ đúng

```python
orders_created_total                    # Counter
api_gateway_request_duration_seconds    # Histogram
payment_amount_dollars                  # Histogram
cache_operations_total                  # Counter
kafka_messages_produced_total           # Counter
db_connection_pool_active               # UpDownCounter
```

❌ Anti-patterns:

```python
order_count           # Thiếu _total
request_duration      # Thiếu unit
paymentAmount         # camelCase
```

### Standard Labels

**Bắt buộc** (từ OTel resource):

- `service_name` (kebab-case)
- `service_version` (semver)

**Phổ biến:**

- `method` (HTTP method)
- `status_code` (HTTP status)
- `endpoint` (route pattern, KHÔNG dùng actual path)
- `status` (business: success/completed/error/out_of_stock)
- `provider` (external: stripe, paypal)

**Từ span metrics** (auto-generated):

- `span_kind`: SPAN_KIND_SERVER, SPAN_KIND_CLIENT
- `status_code`: STATUS_CODE_OK, STATUS_CODE_ERROR

⛔ **TUYỆT ĐỐI KHÔNG dùng** (high-cardinality):

```
http.url, http.target, db.statement, net.peer.ip,
user_id, request_id, trace_id, session_id
```

> **Lý do:** Prometheus không scale tốt với >100k unique time series. Các labels này chỉ nên giữ trong Traces (để debug), KHÔNG đưa vào Metrics.
>
> **Action bắt buộc:** OTel Collector dùng `transform`/`filter` processor để DROP các label trên khỏi METRICS pipeline.

---

## 3️⃣ CUSTOM METRICS (OTel SDK)

**Counter:**

```python
orders_counter = meter.create_counter(
    name="orders_created_total",
    description="Total orders created",
    unit="1",
)
orders_counter.add(1, {"status": "completed", "product_id": str(product_id)})
```

**Histogram (với custom buckets):**

```python
DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

order_duration = meter.create_histogram(
    name="order_processing_duration_seconds",
    description="Order processing duration",
    unit="s",
)
# Apply buckets via View trong otel_setup.py
```

**Gauge (Observable):**

```python
def _pool_active_callback(options):
    yield Observation(pool.get_active_count())

meter.create_observable_gauge(
    name="db_connection_pool_active",
    description="Active DB connections in pool",
    unit="1",
    callbacks=[_pool_active_callback],
)
```

**UpDownCounter (cho pool size):**

```python
db_pool_active = meter.create_up_down_counter(
    name="db_connection_pool_active",
    description="Active database connections",
    unit="1",
)
# .add(1) khi lấy connection, .add(-1) khi trả
```

---

## 4️⃣ LOGGING STANDARDS

### Format

JSON structured logging với `python-json-logger`:

```json
{
  "timestamp": "2026-05-28T10:30:45.123Z",
  "level": "INFO",
  "name": "order-service",
  "message": "Order created successfully",
  "trace_id": "abc123...",
  "span_id": "def456...",
  "order_id": "ORD-789"
}
```

**Fields bắt buộc:**

- `timestamp` (ISO 8601, auto từ python-json-logger)
- `level` (DEBUG/INFO/WARN/ERROR/FATAL)
- `name` (service name)
- `message` (human-readable)

**Auto-injected từ OTel:**

- `trace_id`, `span_id` (correlate logs ↔ traces)
- `trace_flags` (sampling decision)

**Business fields** — Pattern: snake_case

- ✅ `order_id`, `payment_txn_id`, `product_id`, `user_id`
- ❌ `orderId`, `OrderId` (camelCase/PascalCase)

### Log Levels

| Level | Khi nào dùng | Ví dụ |
|-------|-------------|-------|
| `DEBUG` | Chi tiết debug, chỉ bật khi troubleshooting | "Query executed: SELECT * FROM orders" |
| `INFO` | Sự kiện nghiệp vụ quan trọng | "Order created", "Payment completed" |
| `WARN` | Vấn đề không critical, tự recover | "Retry attempt 2/3", "Cache miss" |
| `ERROR` | Lỗi nghiệp vụ hoặc system error | "Payment gateway timeout" |
| `FATAL` | Service không thể tiếp tục | "Cannot connect to required database" |

### Error Logging Pattern

```python
# ✅ Đúng
try:
    result = payment_gateway.charge(amount)
except PaymentGatewayTimeout as e:
    logger.error("Payment gateway timeout",
                 extra={"payment_id": payment_id, "error": str(e)},
                 exc_info=True)
    raise

# ❌ Sai
try:
    result = payment_gateway.charge(amount)
except Exception as e:
    logger.error(f"Error: {e}")  # Thiếu context, không có trace correlation
```

⛔ **Anti-patterns:**

- ❌ Log PII (email, phone, credit card)
- ❌ Dùng `print()` thay vì logger
- ❌ Log exception không có `exc_info=True`
- ❌ Thiếu trace correlation (`trace_id`, `span_id`)
- ❌ Dùng f-string trong log message (dùng structured fields)

---

## 5️⃣ TRACING STANDARDS

### Span Naming

Auto-instrumented spans: giữ nguyên theo OTel Semantic Conventions

- HTTP: `"GET /api/orders/{id}"`
- Database: `"SELECT orders"`
- Messaging: `"orders-topic send"`

Custom business spans: `<domain>.<operation>` (snake_case)

```python
# ✅ Đúng
with tracer.start_as_current_span("catalog.fetch"):
with tracer.start_as_current_span("inventory.check"):
with tracer.start_as_current_span("payment.process"):
with tracer.start_as_current_span("kafka.produce"):

# ❌ Sai
with tracer.start_as_current_span("get_product_catalog"):  # verb_noun
with tracer.start_as_current_span("checkInventory"):       # camelCase
```

### Standard Attributes (OTel Semantic Conventions)

```python
# HTTP
span.set_attribute("http.method", "POST")
span.set_attribute("http.route", "/api/orders")  # Pattern, not actual path
span.set_attribute("http.status_code", 200)

# Database
span.set_attribute("db.system", "postgresql")
span.set_attribute("db.statement", "SELECT * FROM orders WHERE id = ?")  # Redact values
span.set_attribute("db.name", "app_db")
span.set_attribute("db.operation", "SELECT")

# Messaging (Kafka)
span.set_attribute("messaging.system", "kafka")
span.set_attribute("messaging.destination", "order.events")
span.set_attribute("messaging.operation", "publish")
```

### Sampling Strategy

- **SDK Level:** `ParentBasedTraceIdRatio` (100% default, tuân theo upstream)
- **OTel Collector** (Tail Sampling):
  - 100% traces có `status_code=ERROR`
  - 100% traces có latency > 500ms
  - 10% traces bình thường (probabilistic)

---

## 6️⃣ ERROR HANDLING (RFC 7807)

### Response Format

```json
{
  "type": "https://api.lab/errors/insufficient-stock",
  "title": "Insufficient Stock",
  "status": 409,
  "detail": "Product 'Laptop' only has 2 in stock, requested 5",
  "instance": "/orders/ORD-20250512-001",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "error_code": "ERR_INV_OUT_OF_STOCK"
}
```

### Error Code Taxonomy

**Pattern:** `ERR_{DOMAIN}_{PROBLEM}` (UPPERCASE_SNAKE_CASE)

- `ERR_INV_OUT_OF_STOCK` — Inventory insufficient
- `ERR_PAY_GATEWAY_TIMEOUT` — Payment gateway timeout
- `ERR_ORD_INVALID_PAYLOAD` — Invalid request body
- `ERR_AUTH_INVALID_TOKEN` — JWT verification failed
- `ERR_SAGA_COMPENSATION_FAILED` — Saga rollback failed

### Implementation

```python
from shared.errors import problem_response

return problem_response(
    status=409,
    title="Out of Stock",
    detail=f"Insufficient stock for {product['name']}",
    instance="/process",
    extra={
        "order_id": order_id,
        "error_code": "ERR_INV_OUT_OF_STOCK",
        "product_id": product_id,
        "stock_available": current_stock,
        "quantity_requested": quantity
    }
)
```

---

## 7️⃣ HEALTH CHECK ENDPOINTS

### Liveness (`/health/live`)

- **Mục đích:** Process có đang chạy không?
- **Check:** Chỉ return 200 (KHÔNG check dependencies)
- **Action khi fail:** Restart container

```python
@app.route("/health/live")
def liveness():
    return {"status": "alive"}, 200
```

### Readiness (`/health/ready`)

- **Mục đích:** Service có sẵn sàng nhận traffic không?
- **Check:** DB, Cache, Kafka (timeout 2s)
- **Action khi fail:** Ngắt traffic (KHÔNG restart)

```python
@app.route("/health/ready")
def readiness():
    checks = {
        "db": db.check_health(),
        "cache": cache.check_health(),
        "kafka": kafka_producer.check_health()
    }
    all_healthy = all(checks.values())
    status_code = 200 if all_healthy else 503
    return {"status": "ready" if all_healthy else "not_ready", "checks": checks}, status_code
```

> ⚠️ **Critical Rule:** Liveness KHÔNG check DB/Cache. Nếu DB sập, Liveness fail → Kubernetes restart container → CrashLoopBackOff → Sập dây chuyền.

### Usage với shared helper

```python
from shared.health import create_health_blueprint

health_bp = create_health_blueprint("order-service", checks={
    "db": lambda: db.check_health(),
    "cache": lambda: cache.check_health(),
})
app.register_blueprint(health_bp)
```

---

## 8️⃣ KAFKA CONVENTIONS

### Topic Naming

**Pattern:** `<bounded_context>.<entity_stream>` (dot.notation)

```python
# ✅ Đúng
KAFKA_TOPIC = "order.events"          # Existing
KAFKA_TOPIC = "order.shipping"        # Phase 2
KAFKA_TOPIC = "search.sync"           # Phase 3

# ❌ Sai
KAFKA_TOPIC = "orders"                # Quá generic
KAFKA_TOPIC = "order_events"          # snake_case thay vì dot.notation
```

### Event Types

```python
# ✅ Đúng — past tense, specific
event_type = "order.created"
event_type = "order.payment_completed"
event_type = "order.payment_failed"
event_type = "stock.depleted"

# Phase 2 (Saga)
event_type = "order.shipped"
event_type = "order.shipping_failed"
event_type = "order.refunded"
```

### Dead Letter Queue (DLQ)

**Pattern:** `<topic>.dlq`

```python
DLQ_TOPIC = "order.shipping.dlq"  # Saga compensation failures
```

### Producer Pattern

```python
def publish_event(event_type, order_id, data):
    event = {
        "event_type": event_type,
        "event_id": str(uuid.uuid4()),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "order_id": order_id,
        "data": data,
    }
    # Inject trace context
    headers = {}
    inject(headers)
    kafka_headers = [(k, v.encode("utf-8")) for k, v in headers.items()]

    with tracer.start_as_current_span("kafka.produce") as span:
        span.set_attribute("messaging.system", "kafka")
        span.set_attribute("messaging.destination", KAFKA_TOPIC)
        span.set_attribute("messaging.operation", "publish")
        producer.produce(
            topic=KAFKA_TOPIC,
            key=order_id.encode("utf-8"),
            value=json.dumps(event).encode("utf-8"),
            headers=kafka_headers,
            callback=kafka_delivery_callback,
        )
```

### Consumer Pattern (Idempotent Processing)

```python
# Check if already processed
cursor.execute(
    "SELECT 1 FROM processed_events WHERE event_id = %s AND processed_by = %s",
    (event_id, "notification-worker")
)
if cursor.fetchone():
    logger.info(f"Event {event_id} already processed, skipping")
    return

process_notification(event)

cursor.execute(
    "INSERT INTO processed_events (event_id, event_type, processed_by) VALUES (%s, %s, %s)",
    (event_id, event_type, "notification-worker")
)
db.commit()
```

### Graceful Shutdown

```python
import signal, sys

def shutdown_handler(signum, frame):
    logger.info("Received SIGTERM, shutting down gracefully...")
    consumer.close()  # Commits final offsets
    db_connection.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
```

```yaml
# docker-compose.yml
services:
  notification-worker:
    stop_grace_period: 30s
```

---

## 9️⃣ CHECKLISTS

### Khi tạo Service mới

- [ ] Expose `/health/live` và `/health/ready`
- [ ] Setup OTel instrumentation (tracing + metrics)
- [ ] Dùng structured JSON logging
- [ ] Implement RFC 7807 error responses
- [ ] Thêm `healthcheck` trong `docker-compose.yml`
- [ ] Set resource limits (CPU/memory)
- [ ] Configure log rotation
- [ ] Thêm vào Prometheus `scrape_targets`
- [ ] Tạo Grafana dashboard (RED method)
- [ ] Định nghĩa SLI/SLO (nếu customer-facing)

### Khi tạo Kafka Consumer mới

- [ ] Implement idempotent processing (`processed_events` table)
- [ ] Handle SIGTERM gracefully (commit offsets)
- [ ] Set `stop_grace_period: 30s` trong `docker-compose.yml`
- [ ] Emit metrics: `kafka_events_consumed_total`, `processing_duration_seconds`
- [ ] Setup DLQ topic (nếu complex processing)
- [ ] Add to Kafka Overview dashboard

---

## 🔟 FUTURE PATTERNS (Phase 1-6)

### Database Strategy (Hybrid)

```
PostgreSQL instance (:5432)
  ├── app_db          ← Order, Payment, Inventory, Notification
  ├── auth_db         ← Auth Service (isolated)
  └── shipping_db     ← Shipping Service + Worker (isolated)
```

```
DATABASE_URL=postgresql://app_user:***@postgres:5432/app_db
AUTH_DATABASE_URL=postgresql://auth_user:***@postgres:5432/auth_db
SHIPPING_DATABASE_URL=postgresql://shipping_user:***@postgres:5432/shipping_db
```

### Circuit Breaker (`pybreaker`)

```python
import pybreaker

payment_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="payment-service"
)

@payment_breaker
def call_payment_service(order_id, amount):
    return requests.post(f"{PAYMENT_SERVICE}/charge", json={...})
```

**Metrics bắt buộc:**

```python
circuit_breaker_state = meter.create_gauge(
    name="circuit_breaker_state",
    description="CB state (0=closed, 1=open, 2=half_open)",
)
circuit_breaker_failures = meter.create_counter(
    name="circuit_breaker_failures_total",
)
```

**Alert:**

```yaml
alert: CircuitBreakerOpen
expr: circuit_breaker_state{state="open"} == 1
for: 30s
labels:
  severity: warning
```

### Rate Limiting (Redis-based)

```python
rate_limit_global = 100   # requests/second
rate_limit_user = 20      # requests/second per user_id
rate_limit_ip = 50        # requests/second per IP
```

**Response khi rate limited:**

```json
{
  "type": "https://api.lab/errors/rate-limit-exceeded",
  "title": "Rate Limit Exceeded",
  "status": 429,
  "detail": "Too many requests. Please retry after 5 seconds.",
  "error_code": "ERR_RATE_LIMIT",
  "retry_after": 5
}
```

### Saga Pattern (Distributed Transactions)

**State Machine:**

```
INITIATED → PAYMENT_PENDING → PAYMENT_COMPLETED → SHIPPING_PENDING
          → SHIPPED | SHIPPING_FAILED → COMPENSATING → REFUNDED | COMPENSATION_FAILED
```

**Kafka Topics (Phase 2):**

| Topic | Producer | Consumer |
|-------|---------|---------|
| `order.shipped` | Shipping Worker | Notification Worker |
| `order.shipping_failed` | Shipping Worker | Notification Worker |
| `order.refunded` | Shipping Worker | Notification, Inventory Workers |
| `order.shipping.dlq` | Shipping Worker | Manual review |

**Saga Metrics:**

```python
saga_duration = meter.create_histogram(name="saga_duration_seconds")
saga_compensations = meter.create_counter(name="saga_compensations_total")
saga_dlq_size = meter.create_gauge(name="saga_dlq_size")
```

**Saga Alerts:**

```yaml
alert: SagaHighFailureRate
expr: rate(saga_compensations_total[5m]) / rate(saga_duration_seconds_count[5m]) > 0.05
for: 5m
labels:
  severity: critical

alert: SagaDLQGrowing
expr: saga_dlq_size > 10
for: 10m
labels:
  severity: warning
```

### Multi-ID Correlation

```python
logger.info("Order processed", extra={
    "order_id": order_id,
    "user_id": user_id,
    "session_id": session_id,
    "saga_id": saga_id,
})
```

**LogQL Queries:**

```logql
{container_name=~".+"} | json | user_id="user-123"
{container_name=~".+"} | json | user_id="user-123" | saga_id!=""
{container_name=~".+"} | json | order_id="ORD-456"
```

### Synthetic Monitoring (Playwright)

```python
synthetic_journey_duration = meter.create_histogram(name="synthetic_journey_duration_seconds")
synthetic_journey_success = meter.create_counter(name="synthetic_journey_success_total")
```

**Alert:**

```yaml
alert: SyntheticJourneyFailing
expr: rate(synthetic_journey_success_total[10m]) == 0
for: 10m
labels:
  severity: critical
```

### Business Metrics

```python
revenue_dollars = meter.create_histogram(name="revenue_dollars", unit="$")
payment_success = meter.create_counter(name="payment_success_total")
cart_abandonment = meter.create_counter(name="cart_abandonment_total")
```

**Recording Rules:**

```yaml
record: business:revenue_per_hour:1h
expr: sum(rate(revenue_dollars_sum[1h])) / sum(rate(revenue_dollars_count[1h]))

record: business:cart_abandonment_rate:1h
expr: 1 - (sum(rate(cart_checkouts_total[1h])) / sum(rate(cart_additions_total[1h])))
```

---

## ⛔ ANTI-PATTERNS (Application Layer)

**Metrics:**

- ❌ Dùng high-cardinality labels (`user_id`, `request_id`, `http.url`)
- ❌ Tạo metric không có unit (`_total`, `_seconds`, `_bytes`)
- ❌ Dùng camelCase trong metric/label names
- ❌ Tạo quá nhiều custom metrics (ưu tiên span metrics)

**Logging:**

- ❌ Log PII (email, phone, credit card)
- ❌ Dùng `print()` thay vì logger
- ❌ Log exception không có `exc_info=True`
- ❌ Thiếu trace correlation (`trace_id`, `span_id`)

**Kafka:**

- ❌ Không handle SIGTERM (duplicate processing)
- ❌ Không implement idempotency
- ❌ Dùng `snake_case` cho topic names (nên dùng `dot.notation`)
- ❌ Producer không có retry logic

**Database:**

- ❌ Dùng shared database cho tất cả services (khi scale > 10 services)
- ❌ Không có connection pooling
- ❌ Hardcode connection strings trong code
- ❌ Không có backup/restore procedures