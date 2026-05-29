# OBSERVABILITY-INDEX.md — Observability Conventions

> **Mục đích:** Quy tắc cho observability stack — Prometheus, Loki, Tempo, OTel Collector, Grafana dashboards, alerting.
>
> **Khi nào dùng:** Khi user hỏi về monitoring, alerting, dashboards, log queries, trace analysis.
>
> **Cập nhật:** 2026-05-28

---

## 📋 QUICK ROUTING

| Task | Xem section |
|------|-------------|
| Viết recording rule | §1 Recording Rules |
| Tạo alert rule | §2 Alert Rules + §9 Checklist |
| Cấu hình Alertmanager routing | §3 Alertmanager Routing |
| Config OTel Collector | §4 OTel Collector |
| Config Grafana Alloy (log collector) | §5 Grafana Alloy |
| Viết LogQL query | §6 Loki & LogQL |
| Tạo dashboard mới | §7 Dashboard Conventions + §9 Checklist |

---

## 1️⃣ PROMETHEUS RECORDING RULES

### Naming Pattern

`{level}:{metric_name}:{operation}`

### Levels

- `job` — Aggregation theo job
- `instance` — Aggregation theo instance
- `service` — Aggregation theo service_name
- `sli` — SLI metrics (availability, latency...)

### Operations

- `rate5m`, `rate30m`, `rate1h`, `rate6h` — Rate windows
- `sum`, `avg`, `p95`, `p50` — Aggregation type

### Examples

```yaml
# ✅ Đúng
record: service:request_rate:5m
record: instance:cpu_usage_percent:5m
record: sli:api_gateway_availability:rate5m

# ❌ Sai
record: api_gateway_request_rate_5m  # Thiếu level prefix
record: request_rate                 # Quá generic
```

### Group Organization

```yaml
groups:
  - name: app_recording_rules      # Application-level metrics
    interval: 30s
  - name: infra_recording_rules    # Infrastructure metrics
    interval: 30s
  - name: sli_recording_rules      # SLI/SLO metrics (Phase 6)
    interval: 30s
```

### Best Practices

- Luôn dùng `sum by (...)` hoặc `avg by (...)` để giảm cardinality
- Interval chuẩn: `30s` (match với `evaluation_interval`)
- Thêm `or vector(1)` fallback để tránh "no data" khi không có traffic
- Tránh recording rules quá phức tạp (>3 levels of aggregation)

---

## 2️⃣ ALERT RULES

### Naming Pattern

PascalCase: `{Service}{Problem}{Severity?}`

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

### Severity Levels

| Severity | Khi nào dùng | Response time | Ví dụ |
|----------|-------------|---------------|-------|
| `critical` | Service down, data loss risk, SLO fast burn | Immediate (page) | `TargetDown`, `APIGatewayFastBurn` |
| `warning` | Degraded performance, resource pressure, SLO slow burn | Next business day (ticket) | `HighCpuUsage`, `PaymentSlowBurn` |
| `info` | Thông tin, không cần action | Best effort | Deployment notifications |
| `none` | Special (watchdog) | N/A | Watchdog |

### Annotations (Bắt buộc)

```yaml
annotations:
  summary: "🔥 API Gateway fast burn — 2% error budget consumed in 1h"
  description: "Error budget is being consumed 14.4x faster than sustainable."
  runbook: "https://runbooks.lab/RB-APIGW-01-FastBurn"
  dashboard: "https://grafana.lab/d/slo-overview"
```

### `for` Duration Guidelines

- Critical alerts: `1m` - `5m`
- Warning alerts: `5m` - `30m`
- Predictive alerts: `15m` - `30m`
- SLO burn rate: `2m` (fast burn), `15m` (slow burn)

### Traffic Guards (Chống Phantom Alerts)

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

> **Lý do:** Khi traffic stops, `rate()` của custom OTel counters có thể stale → alert fire sai. Dùng span metrics (từ OTel Collector) để check traffic > 0.1 req/s.

### SLO Burn Rate (Multi-Window Multi-Burn-Rate)

**Fast Burn (14.4x) — 2% budget consumed in 1h:**

```yaml
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
```

**Slow Burn (3x) — 10% budget consumed in 6h:**

```yaml
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

---

## 3️⃣ ALERTMANAGER ROUTING

### Group By Strategy

```yaml
group_by: ["alertname", "severity", "job"]
```

> **Lý do:** Group theo `job` (service) để tránh gộp alert từ nhiều services vào 1 notification.

### Severity → Receiver Mapping

| Severity | Receiver | Group Wait | Repeat Interval |
|----------|---------|-----------|----------------|
| `critical` | `telegram-alerts` | `10s` | `1h` |
| `warning` | `telegram-alerts` | `1m` | `4h` |
| `watchdog` | `webhook-alerts` | `30s` | `12h` |

### Inhibition Rules

```yaml
inhibit_rules:
  - source_match:
      severity: "critical"
    target_match:
      severity: "warning"
    equal: ["instance"]
```

---

## 4️⃣ OTEL COLLECTOR CONFIGURATION

### Health Check Filtering

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

### Tail-Based Sampling

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

### Spanmetrics Connector

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

> ⚠️ **Critical:** Chỉ dùng dimensions có cardinality thấp. TUYỆT ĐỐI KHÔNG thêm `http.url`, `user_id`, `trace_id`.

---

## 5️⃣ GRAFANA ALLOY (Log Collection)

### Docker Logs Pipeline

```alloy
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

---

## 6️⃣ LOKI & LOGQL

### Label Strategy

KHÔNG đưa high-cardinality fields vào Loki labels:

```logql
# ❌ Sai — Gây nổ cardinality
labels: [user_id, order_id, trace_id, session_id]

# ✅ Đúng — Chỉ dùng low-cardinality labels
labels: [service_name, container_name, detected_level, source]
```

High-cardinality fields chỉ extract qua LogQL:

```logql
{container_name="order-service"} | json | order_id="ORD-123"
{container_name=~".+"} | json | user_id="user-456" | trace_id!=""
```

### Grafana Derived Fields

Cấu hình regex để biến IDs thành hyperlinks:

- Click `trace_id` → Jump to Tempo
- Click `order_id` → Jump to Order Details dashboard
- Click `user_id` → Jump to User Activity dashboard

### Common LogQL Queries

```logql
# Tất cả logs từ 1 container
{container_name="prometheus"}

# Filter theo text
{container_name="grafana"} |= "error"

# Filter loại trừ
{compose_service="loki"} != "healthcheck"

# Regex filter
{container_name=~".*exporter.*"} |~ "(?i)warn|error"

# Đếm logs/phút theo container
sum by(container_name) (count_over_time({compose_project=~".+"}[1m]))

# Top 5 container nhiều error nhất
topk(5, sum by(container_name) (count_over_time({compose_project=~".+"} |= "error" [5m])))
```

---

## 7️⃣ DASHBOARD CONVENTIONS

### Folder Structure

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

### Variables chuẩn

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

### Panel Titling Convention

`[Metric] — [Aggregation] — [Time Window]`

- "Rate — Request Rate"
- "Duration — Latency (P50 / P95 / P99)"
- "Errors — Error Rate"

### RED Method (Application Dashboards)

Mỗi service có 3 panels chính:

- **Rate** — Request rate (req/s)
- **Errors** — Error rate (%)
- **Duration** — Latency percentiles (P50, P95, P99)

### USE Method (Infrastructure Dashboards)

- **Utilization** — CPU, Memory, Disk usage (%)
- **Saturation** — Queue depth, connection pool usage
- **Errors** — Disk I/O errors, network errors

---

## 8️⃣ PROMETHEUS SCRAPE CONFIG

### Scrape Interval

Chuẩn hóa toàn bộ hệ thống:

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# otel_setup.py
export_interval_millis=15000
```

### Target Categories

- **Local (Observability VM):** `prometheus`, `alertmanager`, `otel-collector`, `node-exporter`, `cadvisor`
- **Remote (App VM `192.168.100.57`):** `node-exporter-app`, `cadvisor-app`, `traffic-gen`, `kafka-exporter`
- **Blackbox probes:** `/health/live` endpoints của tất cả services

---

## 9️⃣ CHECKLISTS

### Khi tạo Alert Rule mới

- [ ] Dùng PascalCase naming
- [ ] Set `severity` phù hợp (`critical`/`warning`/`info`)
- [ ] Thêm annotations: `summary`, `description`, `runbook`, `dashboard`
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

## ⛔ ANTI-PATTERNS (Observability)

**Alerting:**

- ❌ Alert không có runbook
- ❌ Alert quá nhạy (flapping)
- ❌ SLO alert không có traffic guard
- ❌ Dùng `for: 0s` (alert fire ngay)
- ❌ Thiếu annotations (`summary`, `description`)
- ❌ Group alerts quá rộng (notification spam)

**Metrics:**

- ❌ Recording rule quá phức tạp (>3 levels)
- ❌ Không có fallback (`or vector(0)` / `or vector(1)`)
- ❌ Scrape interval không đồng bộ giữa các targets

**Dashboards:**

- ❌ Query không dùng variables (hardcoded)
- ❌ Không có time range selector phù hợp
- ❌ Thiếu units (`s`, `reqps`, `bytes`)
- ❌ Quá nhiều panels trong 1 dashboard (>20)

**Logging:**

- ❌ Loki labels có high cardinality
- ❌ Không drop health check logs (noise)
- ❌ Không chuẩn hóa log levels (`warning` vs `warn`)