# Project Instructions for AI

## 1. Project Context & Philosophy

**Tên dự án:** Observability Lab — Production-Grade E-commerce Microservices  
**Loại dự án:** Lab/Training environment với tiêu chuẩn production-grade  
**Mục đích chính:**
- Thực hành triển khai observability trong kiến trúc Microservices với team size khác nhau (solo → 10+ người)
- Demo các patterns production-grade: distributed tracing, custom metrics, SLO/SLI, incident management
- Nghiên cứu event-driven architecture với Kafka
- Luyện tập incident response với runbook, simulation guide, và post-mortem

**Triết lý:**
- Đây KHÔNG phải toy project — mọi aspect đều hướng đến production-grade
- Docker Compose được sử dụng như production orchestrator (không phải demo tool)
- Tất cả concepts (TLS, secrets, network segmentation, backup, CI, graceful shutdown) đều production-grade
- Chỉ khác Kubernetes ở deployment tooling, không khác ở operational practices

**Ngôn ngữ trả lời:** Tiếng Việt

## 2. Repository Structure

```
on-premises/
├── applications-vm/                    # Business logic + Data layer (60GB RAM)
│   ├── applications/                   # Source code microservices
│   │   ├── api-gateway/               # BFF pattern, rate limiting, JWT verification
│   │   ├── order-service/             # Order processing, Kafka producer, cache-aside
│   │   ├── payment-service/           # Payment processing with simulated latency/errors
│   │   ├── notification-worker/       # Kafka consumer, idempotent processing
│   │   ├── inventory-worker/          # Kafka consumer, stock management, auto-restock
│   │   ├── traffic-gen/               # Load testing tool with scenario templates
│   │   ├── web-ui/                    # Nginx SPA with reverse proxy
│   │   └── shared/                    # Shared modules (db_utils, otel_setup, logging, health, errors, kafka_utils)
│   ├── agents/                        # Monitoring agents (Alloy for log collection)
│   └── docker-compose.yml             # Orchestration cho applications + infrastructure
│
├── observability-vm/                   # Monitoring stack (32GB RAM)
│   ├── phase1-metrics/                # Prometheus + Grafana + Node Exporter + cAdvisor + Alertmanager + Blackbox
│   ├── phase2-logging/                # Loki + Alloy
│   ├── phase3-tracing/                # Tempo + OTel Collector
│   ├── storage/                       # MinIO (S3-compatible) cho Loki chunks + Tempo blocks
│   └── scripts/                       # Utility scripts (annotate.sh, deploy.sh)
│
├── post-mortems/                       # Blameless post-mortem templates và examples
│   ├── 00-TEMPLATE.md                 # Template chuẩn cho post-mortem
│   └── 01-GOLDEN-EXAMPLE-DB-Saturation.md  # Ví dụ mẫu
│
├── ARCHITECTURE.md                     # Kiến trúc chi tiết, data flows, DB schema
├── INCIDENT_RUNBOOK.md                 # Runbook xử lý 24 loại alert
├── INCIDENT_SIMULATION_GUIDE.md        # 12 experiments giả lập incident
├── BREAK_TEST_RECOVERY.md              # 28 exercises break/test/recovery
├── EXPANSION_PLAN.md                   # Kế hoạch mở rộng lên 10 services
├── devops-question.md                  # 45 câu hỏi phỏng vấn (Junior-Mid)
└── devops-question-senior.md           # 31 câu hỏi phỏng vấn (Senior)
```

## 3. Tech Stack Overview

### Core Technologies
- **Language:** Python 3.12 (Flask), Node.js (Express cho web-ui)
- **Database:** PostgreSQL 16 (persistence, connection pooling)
- **Cache:** Redis 7 (cache-aside pattern, TTL 60s)
- **Message Broker:** Apache Kafka 3.7 (KRaft mode, no ZooKeeper)
- **Web Server:** Gunicorn (gthread workers), Nginx (reverse proxy)

### Observability Stack
- **SDK:** OpenTelemetry Python SDK 1.33.*
- **Instrumentations:**
  - Flask (auto)
  - Requests (auto - HTTP client)
  - Psycopg2 (auto - PostgreSQL)
  - Redis (auto)
  - Logging (auto - structured JSON)
- **Collector:** OTel Collector 0.120.0 (tail-based sampling, spanmetrics connector)
- **Exporter:** OTLP over gRPC (:4317) và HTTP (:4318)
- **Backends:**
  - Prometheus v3.10.0 (metrics, recording rules, alerting rules)
  - Loki 3.3.2 (logs, LogQL)
  - Tempo 2.7.0 (traces, TraceQL)
  - Grafana 12.3.3 (dashboards, correlation)
  - Alertmanager v0.28.1 (alert routing → Telegram)
  - Blackbox Exporter v0.25.0 (active health probing)

### Infrastructure
- **Containerization:** Docker (multi-stage builds, security hardened)
- **Orchestration:** Docker Compose (external networks, health checks, depends_on with conditions)
- **Storage:** MinIO (S3-compatible) cho Loki/Tempo long-term storage
- **Monitoring Agents:** Grafana Alloy (log collection từ Docker + host)

## 4. Services Overview

### 4.1 API Gateway (port 5000)
**Chức năng:**
- BFF (Backend for Frontend) pattern
- Routes requests đến backend services
- Error propagation với RFC 7807 format
- Health checks: `/health/live`, `/health/ready`

**Custom Metrics:**
- `api_gateway_requests_total` (counter) - grouped by endpoint, status
- `api_gateway_request_duration_seconds` (histogram)

### 4.2 Order Service (port 5001)
**Chức năng:**
- Xử lý đơn hàng với PostgreSQL persistence
- Cache-aside pattern với Redis (product catalog, TTL 60s)
- Publish events sang Kafka: `order.created`, `order.payment_completed`, `order.payment_failed`, `stock.depleted`
- Gọi HTTP sang Payment Service để thanh toán
- Health checks với dependency validation (DB, Redis)

**Custom Metrics:**
- `orders_created_total` (counter) - grouped by status
- `order_processing_duration_seconds` (histogram)
- `db_query_duration_seconds` (histogram)
- `db_connection_pool_active` (up-down counter)
- `db_connection_pool_max` (observable gauge)
- `cache_operations_total` (counter) - grouped by operation, result
- `cache_operation_duration_seconds` (histogram)
- `kafka_messages_produced_total` (counter)
- `inventory_checks_total` (counter) - grouped by result

### 4.3 Payment Service (port 5002)
**Chức năng:**
- Xử lý thanh toán giả lập (simulate)
- Random delays để demo slow gateway (20% chance)
- Random failures (10% chance)
- Support 3 providers: stripe, paypal, square
- Stateless (không có DB riêng)

**Custom Metrics:**
- `payments_total` (counter) - grouped by status, provider
- `payment_amount_dollars` (histogram)
- `payment_gateway_duration_seconds` (histogram)

### 4.4 Notification Worker (port 5004)
**Chức năng:**
- Kafka consumer từ topic `order.events`
- Consumer group: `notification-workers`
- Idempotent processing qua `processed_events` table
- Gửi notifications (simulate) và persist vào DB
- Graceful shutdown với SIGTERM handler

**Custom Metrics:**
- `notifications_sent_total` (counter) - grouped by type
- `notification_processing_duration_seconds` (histogram)
- `kafka_events_consumed_total` (counter) - grouped by event_type

### 4.5 Inventory Worker (port 5005)
**Chức năng:**
- Kafka consumer từ topic `order.events`
- Consumer group: `inventory-workers`
- Idempotent processing qua `processed_events` table
- Pessimistic locking (SELECT FOR UPDATE) cho stock updates
- Audit trail qua `inventory_log` table
- Auto-restock khi stock < threshold (default: 10)
- Graceful shutdown với SIGTERM handler

**Custom Metrics:**
- `inventory_updates_total` (counter) - grouped by action
- `inventory_processing_duration_seconds` (histogram)
- `kafka_events_consumed_total` (counter) - grouped by event_type
- `inventory_errors_total` (counter)
- `inventory_restock_total` (counter)

### 4.6 Traffic Generator (port 5003)
**Chức năng:**
- Load testing tool với REST API control
- Scenario templates: normal, flash_sale, browse_heavy, health_check, event_driven
- Configurable rate (req/s) và duration
- Prometheus metrics endpoint: `/metrics`

**Custom Metrics:**
- `traffic_gen_running` (gauge)
- `traffic_gen_requests_total` (counter) - grouped by result

### 4.7 Web UI (port 8580)
**Chức năng:**
- Nginx SPA (Single Page Application)
- Reverse proxy đến các services (tránh CORS)
- Dashboard hiển thị orders, products, load testing, events
- Health check: `/health/live`

## 5. Common Patterns & Conventions

### 5.1 Tracing Pattern
Mọi operation quan trọng đều được wrap trong span:
```python
with tracer.start_as_current_span("operation_name") as span:
    span.set_attribute("key", value)
    span.set_attribute("order.id", order_id)
    # business logic
```

**Rules:**
- Span name phải rõ ràng, mô tả operation (không dùng generic names)
- Luôn set attributes cho context (order_id, product_id, status)
- Mark error spans: `span.set_attribute("error", True)`
- Sử dụng auto-instrumentation cho DB, Redis, HTTP clients

### 5.2 Metrics Pattern
**Counter:** dùng `.add(1, {"label": "value"})`
```python
orders_counter.add(1, {"status": "completed", "product_id": str(product_id)})
```

**Histogram:** dùng `.record(value, {"label": "value"})`
```python
order_duration.record(duration, {"status": "completed"})
```

**Labels bắt buộc:**
- Luôn kèm theo context (order_id, status, provider, event_type)
- KHÔNG dùng high-cardinality labels (user_id, request_id, trace_id)
- Convert numbers to strings cho labels: `str(product_id)`

### 5.3 Logging Pattern
**Structured JSON logging** với python-json-logger:
```python
logger.info("Event description", extra={
    "order_id": order_id,
    "amount": total_amount,
    "trace_id": trace_id  # auto-injected by OTel
})
```

**Rules:**
- Luôn dùng `extra={}` dict để thêm context
- KHÔNG dùng f-string trong log message (dùng structured fields)
- Log levels: DEBUG (dev only), INFO (normal operations), WARNING (degraded), ERROR (failures)
- Auto-injected fields: timestamp, level, trace_id, span_id

### 5.4 Error Response Pattern (RFC 7807)
Dùng helper `problem_response()` từ `shared.errors`:
```python
return problem_response(
    status_code=404,
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

### 5.5 Health Checks
Mỗi service đều có 2 endpoints chuẩn Kubernetes/ECS:
```python
health_bp = create_health_blueprint("order-service", checks={
    "db": lambda: db.check_health(),
    "cache": lambda: cache.check_health(),
})
app.register_blueprint(health_bp)
```

**Endpoints:**
- `GET /health/live` - Liveness probe (process alive)
- `GET /health/ready` - Readiness probe (dependencies healthy)
- `GET /health` - Alias của readiness (backward compatibility)

**Rules:**
- Liveness: luôn trả 200 nếu process đang chạy
- Readiness: check tất cả dependencies (DB, Redis, Kafka)
- Trả 503 nếu bất kỳ dependency nào unhealthy

### 5.6 Kafka Event Pattern
**Producer:**
```python
def publish_event(event_type, order_id, data):
    event = {
        "event_type": event_type,
        "event_id": str(uuid.uuid4()),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "order_id": order_id,
        "data": data,
    }
    
    # Inject trace context vào headers
    headers = {}
    inject(headers)
    kafka_headers = [(k, v.encode("utf-8") if isinstance(v, str) else v)
                     for k, v in headers.items()]
    
    producer.produce(
        topic=KAFKA_TOPIC,
        key=order_id.encode("utf-8"),
        value=json.dumps(event).encode("utf-8"),
        headers=kafka_headers,
        callback=kafka_delivery_callback,
    )
```

**Consumer:**
```python
# Extract trace context từ headers
ctx = extract_trace_context(msg.headers())
token = None
if ctx:
    token = otel_context.attach(ctx)

try:
    with tracer.start_as_current_span("kafka.consume") as span:
        # Idempotency check
        if is_event_processed(event_id):
            continue
        
        # Process event
        process_event(event)
        
        # Mark as processed
        mark_event_processed(event_id, event_type)
finally:
    if token:
        otel_context.detach(token)
```

**Rules:**
- Luôn inject/extract trace context qua Kafka headers (W3C traceparent)
- Idempotent processing: check `processed_events` table trước khi process
- Use composite key: `(event_id, processed_by)` để tránh duplicate
- Graceful shutdown: commit offsets trước khi exit

### 5.7 Database Pattern
**Connection Pool:**
```python
db = DatabasePool(DATABASE_URL, minconn=2, maxconn=10,
                  pool_active_counter=db_pool_active,
                  query_duration_histogram=db_query_duration)
```

**Query với metrics:**
```python
rows = db.execute(
    "SELECT * FROM products WHERE id = %s",
    (product_id,)
)
```

**Pessimistic Locking:**
```python
with conn.cursor() as cur:
    cur.execute("SELECT stock FROM products WHERE id = %s FOR UPDATE", (product_id,))
    row = cur.fetchone()
    # Update stock
    cur.execute("UPDATE products SET stock = %s WHERE id = %s", (new_stock, product_id))
    conn.commit()
```

**Rules:**
- Luôn dùng parameterized queries (tránh SQL injection)
- Use connection pooling (SimpleConnectionPool hoặc ThreadedConnectionPool)
- Track connection pool metrics (active, max)
- Track query duration metrics
- Log slow queries (> 100ms)

### 5.8 Cache Pattern (Cache-Aside)
```python
# Try cache first
products = cache.get("product:catalog")

if products is not None:
    span.set_attribute("cache.hit", True)
    return jsonify({"products": products, "source": "cache"})

# Cache miss → query DB
span.set_attribute("cache.hit", False)
rows = db.execute("SELECT * FROM products")
products = [dict(row) for row in rows]

# Set cache
cache.set("product:catalog", products)

return jsonify({"products": products, "source": "database"})
```

**Rules:**
- Always check cache trước khi query DB
- Set cache sau khi query DB (với TTL)
- Invalidate cache khi data thay đổi
- Track cache hit/miss metrics

## 6. Observability Stack

### 6.1 Telemetry Pipeline
```
All Services ──OTLP gRPC──► OTel Collector ──► Prometheus (metrics)
                                            ──► Tempo (traces)
                                            ──► Loki (logs)
                                            ──► Grafana (dashboards)

Blackbox Exporter ──probe /health/live──► Application Services
Prometheus ──scrape──► Blackbox Exporter (probe results)
```

### 6.2 OTel Collector Configuration
**Receivers:**
- OTLP gRPC (:4317)
- OTLP HTTP (:4318)

**Processors:**
- batch (timeout: 5s, send_batch_size: 1000)
- resource (add deployment.environment)
- filter/health (drop health check spans)
- tail_sampling (decision_wait: 10s, num_traces: 50000)

**Tail Sampling Policies:**
1. `keep-errors`: 100% traces với status_code = ERROR
2. `keep-slow-requests`: 100% traces với duration > 500ms
3. `random-sample`: 10% traces bình thường

**Connectors:**
- spanmetrics: auto-generate RED metrics từ traces
  - Histogram buckets: [5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s]
  - Dimensions: http.method, http.status_code, http.route

**Exporters:**
- Prometheus (:8889) - app metrics (manual)
- Prometheus/spanmetrics (:8890) - auto RED metrics
- Tempo (OTLP gRPC)
- Debug (stdout)

### 6.3 Prometheus Configuration
**Scrape Targets:**
- prometheus:9090 (self-monitoring)
- node-exporter:9100 (host metrics)
- cadvisor:8080 (container metrics)
- alertmanager:9093
- otel-collector:8889 (app metrics)
- otel-collector:8890 (span metrics)
- 192.168.100.57:9100 (remote node-exporter)
- 192.168.100.57:8080 (remote cadvisor)
- 192.168.100.57:5003 (traffic-gen)
- 192.168.100.57:9308 (kafka-exporter)
- Blackbox Exporter (active probing)

**Recording Rules:**
- SLI recording rules (availability, latency compliance)
- Service-level aggregations (request rate, error rate, latency)
- Infrastructure aggregations (CPU, memory usage)

**Alert Rules:**
- Infrastructure: TargetDown, HighCpuUsage, HighMemoryUsage, HighDiskUsage
- Predictive: DiskWillFillIn4Hours, MemoryWillExhaustIn2Hours
- SLO Burn Rate: APIGatewayFastBurn, PaymentFastBurn, LatencyFastBurn (MWMBR pattern)
- Kafka: KafkaConsumerLagHigh, KafkaConsumerLagCritical, KafkaConsumerGroupDown
- Application: HighErrorRate, HighLatencyP95, ServiceNoTraces
- Health Check: ServiceHealthCheckFailed

### 6.4 SLO/SLI Definitions
**API Gateway:**
- Availability SLO: 99.5% (non-5xx requests)
- Latency SLO: 95% requests < 500ms

**Payment Service:**
- Success Rate SLO: 99.0%

**MWMBR Alert Thresholds:**
- Fast burn (critical): 14.4x trong 5m + 1h windows → 2% budget consumed trong 1h
- Slow burn (warning): 3x trong 30m + 6h windows → 5% budget consumed trong 6h

**Traffic Guards:**
- Tất cả SLO alerts PHẢI có điều kiện: `rate(total_requests[5m]) > 0.1`
- Ngăn phantom alerts khi không có traffic

### 6.5 Loki Configuration
**Storage:** MinIO (S3-compatible), bucket `loki`
**Retention:** 7 days (168h)
**Schema:** TSDB (v13), 24h index period

**Alloy Pipeline:**
1. Discovery (Docker containers + host logs)
2. Drop health check logs
3. Parse JSON (extract level, msg, trace_id, span_id)
4. Parse logfmt (fallback)
5. Normalize log level (lowercase, warning → warn)
6. Add labels (detected_level, source, vm)
7. Drop debug logs (optional)
8. Push to Loki

### 6.6 Tempo Configuration
**Storage:** MinIO (S3-compatible), bucket `tempo`
**Retention:** 7 days (168h)
**Metrics Generator:**
- Span metrics (RED)
- Service graphs
- Remote write to Prometheus

### 6.7 Grafana Dashboards
**Alerting:**
- alerting-overview: Active alerts, severity, timeline

**Application:**
- unified-overview: Service health at a glance (RPS, Error Rate, Latency)
- app-performance: RED metrics per service
- slo-overview: SLO targets, burn rate, error budget
- kafka-overview: Topic throughput, consumer lag
- db-performance: Query duration, connection pool
- cache-performance: Hit rate, latency

**Infrastructure:**
- node-exporter: Host metrics (CPU, Memory, Disk, Network)
- docker-containers: Container resource usage
- prometheus-self: Prometheus health

**Logging:**
- docker-logs: Container logs
- host-logs: System logs

**Tracing:**
- tracing-overview: RED metrics from spans, service map
- trace-investigation: TraceQL queries

### 6.8 Alertmanager Configuration
**Routing:**
- Default: telegram-alerts
- Watchdog: webhook-alerts (continue: false)
- Critical: telegram-alerts (group_wait: 10s, repeat: 1h, continue: true)
- Warning: telegram-alerts (group_wait: 1m, repeat: 4h, continue: true)
- Catch-all: webhook-alerts

**Inhibition:**
- Critical suppresses warning trên cùng instance

## 7. Rules for AI

### 7.1 Khi Review Code
**Ưu tiên kiểm tra:**
1. **Observability completeness:**
   - Span có được đặt tên rõ ràng không?
   - Attributes có đầy đủ context không? (order_id, status, etc.)
   - Metrics có labels phù hợp không? (không high-cardinality)
   - Error handling có log đủ thông tin không?
   - Trace context có được propagate qua Kafka không?

2. **Reliability patterns:**
   - Idempotent processing cho Kafka consumers?
   - Graceful shutdown handler cho workers?
   - Health checks với dependency validation?
   - Error responses theo RFC 7807?
   - Connection pooling cho DB?
   - Cache-aside pattern cho read-heavy operations?

3. **Security:**
   - Parameterized queries (tránh SQL injection)?
   - Không hardcode secrets trong code?
   - Input validation?

4. **Performance:**
   - Resource leaks (DB connections, Kafka producers)?
   - N+1 query problems?
   - Missing indexes?
   - Cache invalidation đúng cách?

### 7.2 Khi Refactor
**Rules:**
- Giữ nguyên observability patterns đã có
- KHÔNG xóa bỏ auto-instrumentation
- Tuân thủ naming convention hiện tại (snake_case cho functions, PascalCase cho classes)
- Khi thêm feature mới: PHẢI thêm metrics và spans tương ứng
- Khi thay đổi DB schema: PHẢI update init.sql và migration plan
- Khi thay đổi Kafka topics: PHẢI update producers và consumers
- Maintain backward compatibility cho API endpoints

### 7.3 Khi Debug
**Workflow:**
1. **Check Alerting Overview** → Xác định alert nào đang firing
2. **Check Unified Overview** → Service nào bị ảnh hưởng?
3. **Check App Performance** → RED metrics chi tiết
4. **Check Tracing** → Tìm slow traces hoặc error traces
5. **Check DB/Cache/Kafka** → Bottleneck ở đâu?
6. **Check Logs (Loki)** → Error messages, stack traces

**Common issues:**
- **High latency:** Check DB connection pool, slow queries, cache miss rate
- **High error rate:** Check downstream services, DB connectivity, Kafka producer errors
- **Consumer lag:** Check worker health, processing duration, produce rate
- **Phantom alerts:** Check traffic guard conditions, stale metrics

### 7.4 Khi Thêm Service Mới
**Checklist:**
- [ ] Import và setup: `shared/logging_config`, `shared/otel_setup`, `shared/health`, `shared/errors`
- [ ] Implement health checks với `/health/live` và `/health/ready`
- [ ] Add custom metrics cho operations chính (counters, histograms)
- [ ] Wrap operations trong spans với meaningful names và attributes
- [ ] Use structured JSON logging với `extra={}` dict
- [ ] Implement graceful shutdown handler (SIGTERM)
- [ ] Dockerfile multi-stage (builder + runtime)
- [ ] Security hardening: non-root user, read-only filesystem, cap_drop
- [ ] Health check trong Dockerfile
- [ ] Add service vào docker-compose.yml với depends_on conditions
- [ ] Add service vào Blackbox Exporter targets
- [ ] Add service vào Grafana dashboards
- [ ] Document service trong ARCHITECTURE.md

### 7.5 Khi Thêm Alert Mới
**Checklist:**
- [ ] Alert có meaningful name không?
- [ ] Severity phù hợp (critical/warning)?
- [ ] `for` duration hợp lý (tránh false positives)?
- [ ] Annotations có summary và description rõ ràng?
- [ ] Alert có traffic guard để tránh phantom alerts không?
- [ ] Alert có được add vào Grafana dashboard không?
- [ ] Alert có được document trong INCIDENT_RUNBOOK.md không?

### 7.6 Những Điều KHÔNG NÊN Làm
- ❌ KHÔNG hardcode credentials trong production code (dùng environment variables)
- ❌ KHÔNG xóa bỏ OpenTelemetry instrumentation
- ❌ KHÔNG log sensitive data (password, tokens, PII)
- ❌ KHÔNG dùng `print()` - chỉ dùng logger
- ❌ KHÔNG swallow exceptions mà không log
- ❌ KHÔNG dùng high-cardinality labels trong metrics (user_id, request_id)
- ❌ KHÔNG dùng f-string trong log messages (dùng structured fields)
- ❌ KHÔNG bỏ qua idempotency check trong Kafka consumers
- ❌ KHÔNG bỏ qua graceful shutdown handler trong workers
- ❌ KHÔNG tạo alert mà không có traffic guard (cho low-traffic services)

### 7.7 Khi Tham Khảo Tài Liệu Lab
Repo có bộ tài liệu học tập production-grade. Khi trả lời câu hỏi về:
- **Incident response:** Tham khảo `INCIDENT_RUNBOOK.md` (24 alerts với triage steps)
- **Dashboard reading:** Tham khảo `INCIDENT_SIMULATION_GUIDE.md` (12 experiments với Incident Flow)
- **Component internals:** Tham khảo `BREAK_TEST_RECOVERY.md` (28 exercises Break/Test/Recovery)
- **Post-mortem writing:** Tham khảo `post-mortems/00-TEMPLATE.md` và `01-GOLDEN-EXAMPLE-DB-Saturation.md`
- **Expansion planning:** Tham khảo `EXPANSION_PLAN.md` (kế hoạch 6→10 services với Saga, CQRS, Circuit Breaker)
- **Interview prep:** Tham khảo `devops-question.md` (Junior-Mid) và `devops-question-senior.md` (Senior)

### 7.8 Production-Grade Mindset
Khi đưa ra giải pháp, LUÔN cân nhắc:
1. **Team size:** Giải pháp này khả thi cho team 2 người không? 10 người không?
2. **Blast radius:** Nếu giải pháp fail, ảnh hưởng bao nhiêu services?
3. **Rollback plan:** Có thể revert trong < 5 phút không?
4. **Observability:** Sau khi deploy, làm sao biết nó hoạt động đúng?
5. **Operational burden:** Giải pháp này thêm bao nhiêu toil cho on-call engineer?

## 8. Testing Conventions

### Unit Tests
**Framework:** pytest
**Location:** `test_app.py` trong mỗi service directory

**Mocking:**
```python
@pytest.fixture
def client():
    with patch("opentelemetry.sdk.trace.export.BatchSpanProcessor"), \
         patch("opentelemetry.exporter.otlp.proto.grpc.trace_exporter.OTLPSpanExporter"):
        import importlib
        import app as app_module
        importlib.reload(app_module)
        
        app_module.app.config['TESTING'] = True
        with app_module.app.test_client() as test_client:
            yield test_client, app_module
```

**Naming:**
- Test files: `test_*.py`
- Test functions: `test_should_[expected]_when_[condition]` hoặc `test_[feature]_[scenario]`

**Coverage:**
- Health endpoints
- Happy path cho main operations
- Error handling (downstream failures, DB errors, etc.)
- Edge cases (missing data, invalid input)

### Integration Tests
**Framework:** testcontainers (nếu cần)
**Scope:**
- DB operations với real PostgreSQL
- Redis operations với real Redis
- Kafka produce/consume với real Kafka

### Load Testing
**Tool:** Traffic Generator service (port 5003)
**Scenarios:**
- normal: Balanced user activity
- flash_sale: High-volume ordering
- browse_heavy: Mostly browsing
- event_driven: Orders + verify Kafka processing

**API:**
```bash
# Start traffic
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 60}'

# Stop traffic
curl -X POST http://localhost:5003/stop

# Check status
curl http://localhost:5003/status
```

## 9. Deployment & Operations

### Development
```bash
# Start applications VM
cd applications-vm
docker compose up -d

# Start observability VM
cd observability-vm/phase1-metrics
docker compose up -d

cd ../phase2-logging
docker compose up -d

cd ../phase3-tracing
docker compose up -d
```

### Production Considerations
**Gunicorn Configuration:**
```bash
gunicorn \
  --workers 2 \
  --threads 8 \
  --worker-class gthread \
  --bind 0.0.0.0:5001 \
  --access-logfile - \
  --timeout 30 \
  --worker-tmp-dir /dev/shm \
  app:app
```

**Resource Limits:**
```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 512M
    reservations:
      cpus: '0.25'
      memory: 128M
```

**Security Hardening:**
```yaml
read_only: true
tmpfs:
  - /tmp
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

### Monitoring & Alerting
**Dashboards to check:**
1. Alerting Overview - Active alerts
2. Unified Overview - Service health
3. App Performance - RED metrics
4. SLO Overview - Burn rate, error budget
5. Infrastructure - Resource usage

**Alert Response:**
- Follow INCIDENT_RUNBOOK.md for each alert type
- Use INCIDENT_SIMULATION_GUIDE.md for practice
- Write post-mortem using post-mortems/00-TEMPLATE.md

### Backup & Restore
**PostgreSQL:**
```bash
# Backup
docker exec postgres pg_dump -U app -d orders > backup.sql

# Restore
docker exec -i postgres psql -U app -d orders < backup.sql
```

**Kafka:**
- Topic data: Retention policy (default: 7 days)
- Consumer offsets: Stored in `__consumer_offsets` topic

**Grafana:**
- Dashboards: Stored in `grafana/dashboards/` (as code)
- Datasources: Stored in `grafana/provisioning/datasources/`

### Log Rotation
```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

## 10. Expansion Plan (Future Services)

**Planned Services:**
1. **Auth Service (port 5006)** - JWT/RBAC, auth_db (isolated)
2. **Shipping Service (port 5007)** - Shipping management, shipping_db (isolated)
3. **Shipping Worker (port 5008)** - Saga orchestrator, DLQ handling
4. **Search Service (port 5009)** - OpenSearch integration, CQRS pattern

**New Patterns:**
- Saga Orchestration (distributed transactions)
- Circuit Breaker (failure isolation)
- Rate Limiting (Redis-based)
- TLS Termination (HTTPS)
- Secrets Management (Docker secrets)
- Network Segmentation (Docker networks per tier)

**Database Strategy:**
- Hybrid approach: 1 PostgreSQL instance, multiple databases
- app_db: Order, Payment, Inventory, Notification (shared)
- auth_db: Auth Service (isolated for security)
- shipping_db: Shipping Service + Worker (isolated for lifecycle)
- OpenSearch: Search Service (separate engine)

Xem chi tiết trong EXPANSION_PLAN.md

## 11. Questions to Ask Before Making Changes

Trước khi đề xuất thay đổi lớn, hãy hỏi:

1. **Observability Impact:**
   - Thay đổi này có ảnh hưởng đến metrics/logs/traces không?
   - Có cần thêm metrics/spans mới không?
   - Có cần update dashboards không?
   - Có cần thêm alert rules không?

2. **Reliability Impact:**
   - Có ảnh hưởng đến idempotency không?
   - Có cần thêm circuit breaker không?
   - Có ảnh hưởng đến graceful shutdown không?
   - Có cần update health checks không?

3. **Backward Compatibility:**
   - API endpoints có thay đổi không?
   - Kafka message format có thay đổi không?
   - DB schema có thay đổi không?
   - Consumers có cần update không?

4. **Performance Impact:**
   - Có ảnh hưởng đến latency không?
   - Có cần thêm caching không?
   - Có ảnh hưởng đến DB connection pool không?
   - Có cần optimize queries không?

5. **Operational Impact:**
   - Có cần update runbook không?
   - Có cần update simulation guide không?
   - Có cần thêm chaos experiments không?
   - Có ảnh hưởng đến backup/restore không?

## 12. References

**Internal Documentation:**
- ARCHITECTURE.md - Kiến trúc chi tiết
- INCIDENT_RUNBOOK.md - Runbook xử lý 24 loại alert
- INCIDENT_SIMULATION_GUIDE.md - 12 experiments giả lập incident
- BREAK_TEST_RECOVERY.md - 28 exercises break/test/recovery
- EXPANSION_PLAN.md - Kế hoạch mở rộng lên 10 services
- devops-question.md - 45 câu hỏi phỏng vấn (Junior-Mid)
- devops-question-senior.md - 31 câu hỏi phỏng vấn (Senior)
- post-mortems/ - Blameless post-mortem templates

**External References:**
- OpenTelemetry Documentation: https://opentelemetry.io/docs/
- Prometheus Documentation: https://prometheus.io/docs/
- Grafana Documentation: https://grafana.com/docs/
- Kafka Documentation: https://kafka.apache.org/documentation/
- SRE Book: https://sre.google/sre-book/table-of-contents/
- RFC 7807 (Problem Details): https://datatracker.ietf.org/doc/html/rfc7807