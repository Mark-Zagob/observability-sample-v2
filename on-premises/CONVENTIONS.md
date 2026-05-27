# CONVENTIONS.md

> **Mục đích:** File này định nghĩa các quy tắc (conventions) cho dự án Observability Lab.  
> **Đối tượng:** AI assistant, developers, SREs làm việc với codebase này.  
> **Cập nhật lần cuối:** 2026-05-27  
> **Cách dùng với AI Web Chat:** Paste file này + `ARCHITECTURE.md` (~6-7k tokens) ở đầu mỗi session mới.  

---

## 1. Core Identity & Architecture

### 1.1 Project Overview
- **Type:** E-commerce microservices platform (learning lab)
- **Architecture:** Event-driven (Kafka) + Sync HTTP (Flask)
- **Services:** 6 hiện tại → 10 tương lai (Auth, Shipping, Search)
- **Observability:** 3 pillars (Metrics + Logs + Traces) trên VM riêng
- **Deployment:** Docker Compose (2 VMs: Applications VM + Observability VM)

### 1.2 Tech Stack
| Layer | Technology |
|-------|-----------|
| **Application** | Python 3.11+, Flask, psycopg2, redis-py, confluent-kafka |
| **Instrumentation** | OpenTelemetry SDK (auto + manual) |
| **Message Broker** | Kafka 3.7 (KRaft mode) |
| **Database** | PostgreSQL 16, Redis 7 |
| **Observability** | Prometheus, Grafana, Loki, Tempo, OTel Collector, Alloy |
| **Alerting** | Alertmanager → Telegram |
| **Deployment** | Docker Compose |

### 1.3 Data Flow
```
Sync:  Web UI → API Gateway → Order Service → Payment Service
Async: Order Service → Kafka → [Notification Worker, Inventory Worker]
Telemetry: All Services → OTLP gRPC → OTel Collector → [Prometheus, Tempo, Loki]
```

---

## 2. Coding & Instrumentation Standards

### 2.1 Service Naming
- **Pattern:** kebab-case
- **Examples:** `order-service`, `payment-service`, `inventory-worker`
- **Anti-patterns:** `OrderService`, `payment_service`, `inventoryworker`

### 2.2 Metric Naming

#### Pattern
```
{namespace}_{subsystem}_{metric_name}_{unit}
```

#### Units chuẩn
- `_total` - Counter (tích lũy, chỉ tăng)
- `_seconds` - Duration histogram
- `_bytes` - Size
- `_ratio` - Tỉ lệ 0-1
- `_percent` - Tỉ lệ 0-100

#### Examples từ codebase
```python
# ✅ Đúng
orders_created_total
api_gateway_request_duration_seconds
payment_amount_dollars
cache_operations_total
kafka_messages_produced_total

# ❌ Sai
order_count           # Thiếu _total
request_duration      # Thiếu unit
paymentAmount         # camelCase
```

#### Standard Labels
**Bắt buộc (từ OTel resource):**
- `service_name` - kebab-case (VD: `order-service`)
- `service_version` - Semantic versioning

**Phổ biến:**
- `method` - HTTP method (GET, POST...)
- `status_code` - HTTP status code
- `endpoint` - API route pattern (KHÔNG dùng actual path)
- `status` - Business status (`success`, `completed`, `error`, `out_of_stock`)
- `provider` - External service (VD: `stripe`, `paypal`)

**Từ span metrics (auto-generated):**
- `span_kind` - `SPAN_KIND_SERVER`, `SPAN_KIND_CLIENT`
- `status_code` - `STATUS_CODE_OK`, `STATUS_CODE_ERROR`

#### Anti-patterns (TUYỆT ĐỐI KHÔNG dùng)
```python
# ❌ High-cardinality labels (gây nổ Prometheus)
http.url           # Chứa query string/UUID
http.target        # Actual path thay vì route pattern
db.statement       # SQL query với values thật
net.peer.ip        # IP address
user_id            # User identifier
request_id         # Request identifier
trace_id           # Trace identifier (chỉ dùng trong traces)
```

**Lý do:** Prometheus không scale tốt với >100k unique time series. Các labels này chỉ nên giữ trong **Traces** (để debug), KHÔNG đưa vào **Metrics**.

**Action bắt buộc:** Cấu hình OTel Collector (dùng `transform` hoặc `filter` processor) để DROP các label trên khỏi METRICS pipeline.

### 2.3 Custom Metrics (OTel SDK)

#### Counter
```python
orders_counter = meter.create_counter(
    name="orders_created_total",
    description="Total orders created",
    unit="1",
)
orders_counter.add(1, {"status": "completed", "product_id": "123"})
```

#### Histogram (Custom Buckets)
```python
# Custom buckets cho latency (seconds)
DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

order_duration = meter.create_histogram(
    name="order_processing_duration_seconds",
    description="Order processing duration in seconds",
    unit="s",
)
# Apply custom buckets via View (xem otel_setup.py)
```

#### Gauge (Observable)
```python
def _pool_active_callback(options):
    yield Observation(pool.get_active_count())

meter.create_observable_gauge(
    name="db_connection_pool_active",
    description="Active database connections in pool",
    unit="1",
    callbacks=[_pool_active_callback],
)
```

### 2.4 Logging Standards

#### Format
**JSON structured logging** với fields chuẩn:
```json
{
  "timestamp": "2026-05-27T10:30:45.123Z",
  "level": "INFO",
  "name": "order-service",
  "message": "Order created successfully",
  "trace_id": "abc123...",
  "span_id": "def456...",
  "order_id": "ORD-789"
}
```

#### Fields bắt buộc
- `timestamp` - ISO 8601 format (auto từ python-json-logger)
- `level` - DEBUG/INFO/WARN/ERROR/FATAL
- `name` - Logger name (service name)
- `message` - Human-readable message

#### Fields tự động inject từ OTel
- `trace_id`, `span_id` - Để correlate logs với traces
- `trace_flags` - Sampling decision

#### Business-specific fields
- **Pattern:** snake_case
- **Examples:** `order_id`, `payment_txn_id`, `product_id`, `user_id`
- **Anti-patterns:** camelCase (`orderId`), PascalCase (`OrderId`)

#### Log Levels
| Level | Khi nào dùng | Ví dụ |
|-------|--------------|-------|
| **DEBUG** | Chi tiết debug, chỉ bật khi troubleshooting | `"Query executed: SELECT * FROM orders"` |
| **INFO** | Sự kiện nghiệp vụ quan trọng | `"Order created"`, `"Payment completed"` |
| **WARN** | Vấn đề không critical, có thể tự recover | `"Retry attempt 2/3"`, `"Cache miss"` |
| **ERROR** | Lỗi nghiệp vụ hoặc system error cần attention | `"Payment gateway timeout"` |
| **FATAL** | Service không thể tiếp tục chạy | `"Cannot connect to required database"` |

#### Error Logging Pattern
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

**Best practices:**
- Luôn dùng `exc_info=True` khi log exception
- Thêm business context qua `extra={}` parameter
- KHÔNG log PII (email, phone, credit card numbers)

### 2.5 Tracing Standards

#### Span Naming
**Auto-instrumented spans:** Giữ nguyên theo OTel Semantic Conventions
- HTTP: `"GET /api/orders/{id}"`
- Database: `"SELECT orders"`
- Messaging: `"orders-topic send"`

**Custom business spans:** Pattern `<domain>.<operation>` (snake_case)
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

#### Standard Attributes (OTel Semantic Conventions)
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

#### Sampling Strategy
- **SDK Level:** `ParentBasedTraceIdRatio` (100% default, tuân theo upstream)
- **OTel Collector Level (Tail Sampling):**
  - Giữ **100%** traces có `status_code=ERROR`
  - Giữ **100%** traces có `latency > 500ms`
  - Giữ **10%** traces bình thường (probabilistic)

### 2.6 Error Handling (RFC 7807)

#### Response Format
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

#### Error Code Taxonomy
**Pattern:** `ERR_{DOMAIN}_{PROBLEM}` (UPPERCASE_SNAKE_CASE)

**Examples:**
- `ERR_INV_OUT_OF_STOCK` - Inventory insufficient
- `ERR_PAY_GATEWAY_TIMEOUT` - Payment gateway timeout
- `ERR_ORD_INVALID_PAYLOAD` - Invalid request body
- `ERR_AUTH_INVALID_TOKEN` - JWT verification failed
- `ERR_SAGA_COMPENSATION_FAILED` - Saga rollback failed

#### Implementation
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

### 2.7 Health Check Endpoints

#### Liveness (`/health/live`)
- **Mục đích:** Process có đang chạy không?
- **Check:** Chỉ return 200 (KHÔNG check dependencies)
- **Action khi fail:** Restart container
- **Blackbox Exporter:** Probe endpoint này

```python
@app.route("/health/live")
def liveness():
    return {"status": "alive"}, 200
```

#### Readiness (`/health/ready`)
- **Mục đích:** Service có sẵn sàng nhận traffic không?
- **Check:** DB, Cache, Kafka (timeout 2s)
- **Action khi fail:** Ngắt traffic khỏi load balancer (KHÔNG restart)

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

**⚠️ Critical:** Liveness KHÔNG check DB/Cache. Nếu DB sập, Liveness fail → Kubernetes restart container → CrashLoopBackOff → Sập dây chuyền.

### 2.8 Kafka Conventions

#### Topic Naming
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

#### Event Types
```python
# ✅ Đúng - past tense, specific
event_type = "order.created"
event_type = "order.payment_completed"
event_type = "order.payment_failed"
event_type = "stock.depleted"

# Phase 2 (Saga)
event_type = "order.shipped"
event_type = "order.shipping_failed"
event_type = "order.refunded"
```

#### Dead Letter Queue (DLQ)
**Pattern:** `<topic>.dlq`
```python
DLQ_TOPIC = "order.shipping.dlq"  # Saga compensation failures
```

#### Producer Pattern
```python
def publish_event(event_type, order_id, data):
    event = {
        "event_type": event_type,
        "event_id": str(uuid.uuid4()),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "order_id": order_id,
        "data": data,
    }
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

#### Consumer Pattern (Idempotent Processing)
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

#### Graceful Shutdown
```python
import signal, sys

def shutdown_handler(signum, frame):
    logger.info("Received SIGTERM, shutting down gracefully...")
    consumer.close()  # Commits final offsets
    db_connection.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
```

**docker-compose.yml:**
```yaml
services:
  notification-worker:
    stop_grace_period: 30s
```

---

## 3. Observability & Infrastructure Standards

### 3.1 Prometheus Recording Rules

#### Naming Pattern
```
{level}:{metric_name}:{operation}
```

#### Levels
- `job` - Aggregation theo job
- `instance` - Aggregation theo instance
- `service` - Aggregation theo service_name
- `sli` - SLI metrics (availability, latency...)

#### Operations
- `rate5m`, `rate30m`, `rate1h`, `rate6h` - Rate windows
- `sum`, `avg`, `p95`, `p50` - Aggregation type

#### Examples
```yaml
# ✅ Đúng
record: service:request_rate:5m
record: instance:cpu_usage_percent:5m
record: sli:api_gateway_availability:rate5m

# ❌ Sai
record: api_gateway_request_rate_5m  # Thiếu level prefix
record: request_rate                 # Quá generic
```

#### Group Organization
```yaml
groups:
  - name: app_recording_rules      # Application-level metrics
    interval: 30s
  - name: infra_recording_rules    # Infrastructure metrics
    interval: 30s
  - name: sli_recording_rules      # SLI/SLO metrics (Phase 6)
    interval: 30s
```

#### Best Practices
- Luôn dùng `sum by (...)` hoặc `avg by (...)` để giảm cardinality
- Interval chuẩn: `30s` (match với evaluation_interval)
- Thêm `or vector(1)` fallback để tránh "no data" khi không có traffic
- Tránh recording rules quá phức tạp (>3 levels of aggregation)

### 3.2 Alert Rules

#### Naming Pattern
```
PascalCase: {Service}{Problem}{Severity?}
```

#### Examples
```yaml
# ✅ Đúng
alert: TargetDown
alert: HighCpuUsage
alert: APIGatewayFastBurn
alert: PaymentSlowBurn
alert: KafkaConsumerLagHigh

# ❌ Sai
alert: high_cpu_usage                   # Không PascalCase
alert: cpu_alert                        # Quá generic
alert: api_gateway_fast_burn_rate_alert # Quá dài
```

#### Severity Levels
| Severity | Khi nào dùng | Response time | Ví dụ |
|----------|--------------|---------------|-------|
| **critical** | Service down, data loss risk, SLO fast burn | Immediate (page) | `TargetDown`, `APIGatewayFastBurn` |
| **warning** | Degraded performance, resource pressure, SLO slow burn | Next business day (ticket) | `HighCpuUsage`, `PaymentSlowBurn` |
| **info** | Thông tin, không cần action | Best effort | Deployment notifications |
| **none** | Special (watchdog) | N/A | `Watchdog` |

#### Annotations (Bắt buộc)
```yaml
annotations:
  summary: "🔥 API Gateway fast burn — 2% error budget consumed in 1h"
  description: "Error budget is being consumed 14.4x faster than sustainable."
  runbook: "https://runbooks.lab/RB-APIGW-01-FastBurn"
  dashboard: "https://grafana.lab/d/slo-overview"
```

#### `for` Duration Guidelines
- **Critical alerts:** `1m - 5m`
- **Warning alerts:** `5m - 30m`
- **Predictive alerts:** `15m - 30m`
- **SLO burn rate:** `2m` (fast burn), `15m` (slow burn)

#### Traffic Guards (Chống Phantom Alerts)
```yaml
alert: APIGatewayFastBurn
expr: |
  (
    (1 - sli:api_gateway_availability:rate5m) / (1 - 0.995) > 14.4
    and
    (1 - sli:api_gateway_availability:rate1h) / (1 - 0.995) > 14.4
    and
    sum(rate(traces_spanmetrics_calls_total{service_name="api-gateway"}[5m])) > 0.1
  )
```

**Lý do:** Khi traffic stops, `rate()` của custom OTel counters có thể stale → alert fire sai. Dùng span metrics (từ OTel Collector) để check traffic > 0.1 req/s.

#### SLO Burn Rate (Multi-Window Multi-Burn-Rate)
```yaml
# Fast Burn (14.4x) - 2% budget consumed in 1h
alert: APIGatewayFastBurn
expr: |
  (1 - sli:api_gateway_availability:rate5m) / (1 - 0.995) > 14.4
  and
  (1 - sli:api_gateway_availability:rate1h) / (1 - 0.995) > 14.4
for: 2m
labels:
  severity: critical
  slo: api_gateway_availability
  burn_window: fast

# Slow Burn (3x) - 10% budget consumed in 6h
alert: APIGatewaySlowBurn
expr: |
  (1 - sli:api_gateway_availability:rate30m) / (1 - 0.995) > 3
  and
  (1 - sli:api_gateway_availability:rate6h) / (1 - 0.995) > 3
for: 15m
labels:
  severity: warning
  slo: api_gateway_availability
  burn_window: slow
```

### 3.3 Alertmanager Routing

#### Group By Strategy
```yaml
group_by: ["alertname", "severity", "job"]
```

**Lý do:** Group theo `job` (service) để tránh gộp alert từ nhiều services vào 1 notification.

#### Severity → Receiver Mapping
| Severity | Receiver | Group Wait | Repeat Interval |
|----------|----------|------------|-----------------|
| **critical** | telegram-alerts | 10s | 1h |
| **warning** | telegram-alerts | 1m | 4h |
| **watchdog** | webhook-alerts | 30s | 12h |

#### Inhibition Rules
```yaml
- source_match:
    severity: "critical"
  target_match:
    severity: "warning"
  equal: ["instance"]
```

### 3.4 OTel Collector Configuration

#### Health Check Filtering
```yaml
processors:
  filter/health:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'
        - 'attributes["http.route"] == "/ready"'
        - 'attributes["url.path"] == "/health"'
```

#### Tail-Based Sampling
```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    policies:
      - name: keep-errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: keep-slow-requests
        type: latency
        latency:
          threshold_ms: 500
      - name: random-sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 10
```

#### Spanmetrics Connector
```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s]
    dimensions:
      - name: http.method
      - name: http.status_code
      - name: http.route
    namespace: span
```

**⚠️ Critical:** Chỉ dùng dimensions có cardinality thấp. TUYỆT ĐỐI KHÔNG thêm `http.url`, `user_id`, `trace_id`.

### 3.5 Grafana Alloy (Log Collection)

#### Docker Logs Pipeline
```hcl
loki.process "docker_pipeline" {
  stage.drop {
    expression = "(?i)(GET|HEAD)\\s+/(health|ready|healthz)"
    drop_counter_reason = "health_check"
  }

  stage.json {
    expressions = {
      level    = "level",
      msg      = "msg",
      trace_id = "trace_id",
      span_id  = "span_id",
    }
  }

  stage.template {
    source   = "level"
    template = "{{ ToLower .Value }}"
  }

  stage.replace {
    expression = "warning"
    source     = "level"
    replace    = "warn"
  }

  stage.labels {
    values = {
      detected_level = "level",
    }
  }

  stage.drop {
    source              = "level"
    expression          = "debug"
    drop_counter_reason = "debug_level"
  }

  forward_to = [loki.write.loki_endpoint.receiver]
}
```

### 3.6 Loki & LogQL

#### Label Strategy
**KHÔNG đưa high-cardinality fields vào Loki labels:**
```yaml
# ❌ Sai - Gây nổ cardinality
labels: [user_id, order_id, trace_id, session_id]

# ✅ Đúng - Chỉ dùng low-cardinality labels
labels: [service_name, container_name, detected_level, source]
```

**High-cardinality fields chỉ extract qua LogQL:**
```logql
{container_name="order-service"} | json | order_id="ORD-123"
{container_name=~".+"} | json | user_id="user-456" | trace_id!=""
```

#### Grafana Derived Fields
Cấu hình regex để biến IDs thành hyperlinks:
- Click `trace_id` → Jump to Tempo
- Click `order_id` → Jump to Order Details dashboard
- Click `user_id` → Jump to User Activity dashboard

### 3.7 Dashboard Conventions

#### Folder Structure
```
Application/
  ├── app-performance.json
  ├── cache-performance.json
  ├── db-performance.json
  ├── kafka-overview.json
  ├── slo-overview.json
  └── unified-overview.json

Infrastructure/
  ├── docker-containers.json
  ├── node-exporter.json
  └── prometheus-self.json

Logging/
  ├── docker-logs.json
  └── host-logs.json

Tracing/
  ├── trace-investigation.json
  └── tracing-overview.json

Alerting/
  └── alerting-overview.json
```

#### Variables chuẩn
```json
{
  "templating": {
    "list": [
      {
        "name": "service",
        "type": "query",
        "query": "label_values(traces_spanmetrics_calls_total, service_name)"
      },
      {
        "name": "instance",
        "type": "query",
        "query": "label_values(up{job=\"$service\"}, instance)"
      }
    ]
  }
}
```

#### Panel Titling Convention
```
[Metric] — [Aggregation] — [Time Window]

Examples:
- "Rate — Request Rate"
- "Duration — Latency (P50 / P95 / P99)"
- "Errors — Error Rate"
```

#### RED Method (Application Dashboards)
Mỗi service có 3 panels chính:
1. **Rate** - Request rate (req/s)
2. **Errors** - Error rate (%)
3. **Duration** - Latency percentiles (P50, P95, P99)

#### USE Method (Infrastructure Dashboards)
1. **Utilization** - CPU, Memory, Disk usage (%)
2. **Saturation** - Queue depth, connection pool usage
3. **Errors** - Disk I/O errors, network errors

---

## 4. Future-Proof Conventions (Phase 1-6)

### 4.1 Database Strategy (Hybrid)
```
PostgreSQL instance (:5432)
  ├── app_db          ← Order, Payment, Inventory, Notification
  ├── auth_db         ← Auth Service (isolated)
  └── shipping_db     ← Shipping Service + Worker (isolated)
```

**Connection Strings:**
```bash
DATABASE_URL=postgresql://app_user:***@postgres:5432/app_db
AUTH_DATABASE_URL=postgresql://auth_user:***@postgres:5432/auth_db
SHIPPING_DATABASE_URL=postgresql://shipping_user:***@postgres:5432/shipping_db
```

### 4.2 Circuit Breaker (pybreaker)
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

**Metrics (Bắt buộc):**
```python
circuit_breaker_state = meter.create_gauge(
    name="circuit_breaker_state",
    description="Circuit breaker state (0=closed, 1=open, 2=half_open)",
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

### 4.3 Rate Limiting (Redis-based)
```python
rate_limit_global = 100  # requests/second
rate_limit_user = 20     # requests/second per user_id
rate_limit_ip = 50       # requests/second per IP
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

### 4.4 Saga Pattern (Distributed Transactions)

#### State Machine
```
INITIATED → PAYMENT_PENDING → PAYMENT_COMPLETED → SHIPPING_PENDING
          → SHIPPED | SHIPPING_FAILED → COMPENSATING → REFUNDED | COMPENSATION_FAILED
```

#### Kafka Topics
| Topic | Producer | Consumer |
|-------|----------|----------|
| `order.shipped` | Shipping Worker | Notification Worker |
| `order.shipping_failed` | Shipping Worker | Notification Worker |
| `order.refunded` | Shipping Worker | Notification, Inventory Workers |
| `order.shipping.dlq` | Shipping Worker | Manual review |

#### Saga Metrics
```python
saga_duration = meter.create_histogram(name="saga_duration_seconds")
saga_compensations = meter.create_counter(name="saga_compensations_total")
saga_dlq_size = meter.create_gauge(name="saga_dlq_size")
```

#### Saga Alerts
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

### 4.5 Multi-ID Correlation

#### Enrich Logs với Multiple IDs
```python
logger.info("Order processed", extra={
    "order_id": order_id,
    "user_id": user_id,
    "session_id": session_id,
    "saga_id": saga_id,
})
```

#### LogQL Queries
```logql
{container_name=~".+"} | json | user_id="user-123"
{container_name=~".+"} | json | user_id="user-123" | saga_id!=""
{container_name=~".+"} | json | order_id="ORD-456"
```

### 4.6 Synthetic Monitoring (Playwright)

#### Metrics
```python
synthetic_journey_duration = meter.create_histogram(name="synthetic_journey_duration_seconds")
synthetic_journey_success = meter.create_counter(name="synthetic_journey_success_total")
```

#### Alert
```yaml
alert: SyntheticJourneyFailing
expr: rate(synthetic_journey_success_total[10m]) == 0
for: 10m
labels:
  severity: critical
```

### 4.7 Business Metrics

#### Examples
```python
revenue_dollars = meter.create_histogram(name="revenue_dollars", unit="$")
payment_success = meter.create_counter(name="payment_success_total")
cart_abandonment = meter.create_counter(name="cart_abandonment_total")
```

#### Recording Rules
```yaml
record: business:revenue_per_hour:1h
expr: sum(rate(revenue_dollars_sum[1h])) / sum(rate(revenue_dollars_count[1h]))

record: business:cart_abandonment_rate:1h
expr: 1 - (sum(rate(cart_checkouts_total[1h])) / sum(rate(cart_additions_total[1h])))
```

---

## 5. Infrastructure & Deployment

### 5.1 Docker Compose Standards

#### Health Checks
```yaml
services:
  order-service:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

#### Resource Limits
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
```

#### Log Rotation
```yaml
services:
  order-service:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

#### Network Segmentation
```yaml
networks:
  frontend:
  backend:
  data:
  observability:

services:
  web-ui:
    networks: [frontend]
  api-gateway:
    networks: [frontend, backend]
  order-service:
    networks: [backend, data]
  postgres:
    networks: [data]
```

### 5.2 Scrape Interval
**Chuẩn hóa toàn bộ hệ thống:**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# otel_setup.py
export_interval_millis=15000
```

### 5.3 Backup & Restore
```bash
# Backup per-database
pg_dump -h localhost -U app_user app_db > backup/app_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U auth_user auth_db > backup/auth_db_$(date +%Y%m%d).sql

# Restore
pg_restore -h localhost -U app_user -d app_db < backup/app_db_20260527.sql
```

**Schedule:** Daily (cron)
**Retention:** 7 days local
**RTO:** 30 min | **RPO:** 24h

---

## 6. Security & Secrets

### 6.1 Secrets Management
```yaml
services:
  order-service:
    env_file: .env.order
    secrets:
      - db_password
      - jwt_public_key

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_public_key:
    file: ./secrets/jwt_public.pem
```

**Rules:**
- `.env.*` files trong `.gitignore`
- `secrets/` directory với `chmod 600`
- KHÔNG hardcode secrets trong code hoặc docker-compose.yml

### 6.2 TLS Termination
```
Client ──HTTPS──► nginx (TLS termination) ──HTTP──► API Gateway ──► services
```

**Internal traffic:** HTTP (within Docker network)
**External traffic:** HTTPS (nginx reverse proxy)

### 6.3 JWT Authentication
```python
from jwt import decode, PyJWKClient

jwks_client = PyJWKClient("https://auth-service:5006/.well-known/jwks.json")

def verify_jwt(token):
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    return decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience="api-gateway"
    )
```

**Key Rotation:**
1. Generate new key pair
2. Deploy new public key (keep old one valid)
3. Switch to new private key for signing
4. Wait for old tokens to expire (15 min)
5. Remove old public key

---

## 7. Testing & CI/CD

### 7.1 Performance Testing (k6)
```javascript
export const options = {
  thresholds: {
    http_req_duration: ['p(99)<500'],
    http_req_failed: ['rate<0.005'],
  },
};
```

**CI Gate:** Auto-fail PR nếu thresholds violated.

### 7.2 Contract Testing (Pact)
```python
def test_order_event_contract():
    (pact
     .given("an order exists")
     .upon_receiving("a request to process order")
     .with_request("POST", "/shipping/create")
     .will_respond_with(200, body={"status": "shipped"}))
```

### 7.3 CI Pipeline (GitHub Actions)
```yaml
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
        run: docker compose build
      - name: Health check smoke test
        run: |
          docker compose up -d
          sleep 30
          curl -f http://localhost:5000/health/live
          docker compose down
```

---

## 8. Checklist cho Developers

### Khi tạo Service mới
- [ ] Expose `/health/live` và `/health/ready`
- [ ] Setup OTel instrumentation (tracing + metrics)
- [ ] Dùng structured JSON logging
- [ ] Implement RFC 7807 error responses
- [ ] Thêm healthcheck trong docker-compose.yml
- [ ] Set resource limits (CPU/memory)
- [ ] Configure log rotation
- [ ] Thêm vào Prometheus scrape_targets
- [ ] Tạo Grafana dashboard (RED method)
- [ ] Định nghĩa SLI/SLO (nếu customer-facing)

### Khi tạo Kafka Consumer mới
- [ ] Implement idempotent processing (processed_events table)
- [ ] Handle SIGTERM gracefully (commit offsets)
- [ ] Set `stop_grace_period: 30s` trong docker-compose.yml
- [ ] Emit metrics: `kafka_events_consumed_total`, `processing_duration_seconds`
- [ ] Setup DLQ topic (nếu complex processing)
- [ ] Add to Kafka Overview dashboard

### Khi tạo Alert Rule mới
- [ ] Dùng PascalCase naming
- [ ] Set severity phù hợp (critical/warning/info)
- [ ] Thêm annotations: summary, description, runbook, dashboard
- [ ] Dùng traffic guard (nếu SLO alert)
- [ ] Test với `promtool check rules alert_rules.yml`
- [ ] Verify alert route trong Alertmanager

### Khi tạo Dashboard mới
- [ ] Organize theo folder structure
- [ ] Dùng variables: `$service`, `$instance`, `$__rate_interval`
- [ ] Apply RED method (Rate, Errors, Duration)
- [ ] Thêm links đến related dashboards
- [ ] Test với different time ranges

---

## 9. Anti-Patterns (TUYỆT ĐỐI TRÁNH)

### Metrics
- ❌ Dùng high-cardinality labels (`user_id`, `request_id`, `http.url`)
- ❌ Tạo metric không có unit (`_total`, `_seconds`, `_bytes`)
- ❌ Dùng camelCase trong metric/label names
- ❌ Tạo quá nhiều custom metrics (ưu tiên span metrics)

### Logging
- ❌ Log PII (email, phone, credit card)
- ❌ Dùng `print()` thay vì logger
- ❌ Log exception không có `exc_info=True`
- ❌ Thiếu trace correlation (`trace_id`, `span_id`)

### Alerting
- ❌ Alert không có runbook
- ❌ Alert quá nhạy (flapping)
- ❌ SLO alert không có traffic guard
- ❌ Dùng `for: 0s` (alert fire ngay)

### Kafka
- ❌ Không handle SIGTERM (duplicate processing)
- ❌ Không implement idempotency
- ❌ Dùng snake_case cho topic names (nên dùng dot.notation)
- ❌ Producer không có retry logic

### Database
- ❌ Dùng shared database cho tất cả services (khi scale > 10 services)
- ❌ Không có connection pooling
- ❌ Hardcode connection strings trong code
- ❌ Không có backup/restore procedures

### Infrastructure
- ❌ Không set resource limits (OOM killer)
- ❌ Không có log rotation (disk full)
- ❌ Liveness probe check DB/Cache (CrashLoopBackOff)
- ❌ Hardcode secrets trong docker-compose.yml

---

## 10. Resources & References

### Internal Documentation
- `ARCHITECTURE.md` - System architecture overview
- `EXPANSION_PLAN.md` - Roadmap cho Phase 1-6
- `INCIDENT_RUNBOOK.md` - Incident response procedures
- `BREAK_TEST_RECOVERY.md` - Chaos engineering scenarios

### External References
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)
- [RFC 7807 - Problem Details for HTTP APIs](https://datatracker.ietf.org/doc/html/rfc7807)
- [RED Method](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
- [USE Method](http://www.brendangregg.com/usemethod.html)

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-05-27 | 1.0 | Initial version - Compiled from Tier 1-3 analysis |

---

**End of CONVENTIONS.md**