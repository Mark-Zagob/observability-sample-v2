# 📊 Dashboard Reading & Incident Simulation Guide

## Mục tiêu

Hướng dẫn đọc dashboard theo chuẩn production-grade bằng phương pháp **Incident Flow** — đi theo luồng sự cố thực tế thay vì đọc từng dashboard rời rạc. Kèm 8 bài thực hành giả lập incident trên hệ thống hiện tại.

> **Prerequisite:** Hệ thống observability-sample-v2 đang chạy (applications-vm + observability-vm).

---

## Part 1: Phương pháp đọc Dashboard

### 1.1 Hai phương pháp chuẩn ngành

| Phương pháp | Áp dụng cho | Câu hỏi trả lời |
|-------------|-------------|------------------|
| **RED** (Rate, Errors, Duration) | Application / Service | Service có hoạt động tốt không? |
| **USE** (Utilization, Saturation, Errors) | Infrastructure / Resource | Resource có đủ không? |

> **Quan trọng:** RED cho services, USE cho resources. Đừng dùng ngược — hỏi "utilization" của API Gateway vô nghĩa, hỏi "request rate" của CPU cũng vậy.

### 1.2 Dashboard Inventory

| Folder | Dashboard | Vai trò |
|--------|-----------|---------|
| Alerting | alerting-overview | Alert status, severity, timeline |
| Application | unified-overview | Service health tổng quan (RPS, Error, Latency) |
| Application | app-performance | RED metrics chi tiết từng service |
| Application | slo-overview | SLO targets, error budget, burn rate |
| Application | kafka-overview | Event pipeline: produce/consume rate, lag |
| Application | db-performance | Query duration, connection pool |
| Application | cache-performance | Hit rate, latency, evictions |
| Infrastructure | node-exporter | Host metrics: CPU, Memory, Disk, Network |
| Infrastructure | docker-containers | Container resource usage, restart count |
| Infrastructure | prometheus-self | Prometheus health & performance |
| Logging | docker-logs | Container logs (Loki) |
| Logging | host-logs | System logs |
| Tracing | tracing-overview | Trace count, error traces, span durations |
| Tracing | trace-investigation | Deep-dive trace analysis |

### 1.3 Incident Flow — Đọc dashboard theo luồng sự cố

```
                    ┌─────────────────────┐
                    │  🔔 Alert Firing     │  ← Điểm bắt đầu
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
              ①    │  Alerting Overview   │  Alert nào? Severity? Bao lâu rồi?
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
              ②    │  Unified Overview    │  Service nào ảnh hưởng? Phạm vi?
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼─────┐  ┌──────▼──────┐  ┌──────▼──────┐
③  │App Performance│  │SLO Overview │  │Infrastructure│
    │  RED metrics   │  │Error Budget │  │  USE metrics │
    └─────────┬─────┘  └─────────────┘  └──────────────┘
              │
    ┌─────────▼─────────┐
④  │  Tracing Overview  │  Request chain? Span nào chậm?
    └─────────┬─────────┘
              │
    ┌─────────▼─────────────────────────────┐
⑤  │  DB / Cache / Kafka Performance       │  Bottleneck ở đâu?
    └───────────────────────────────────────┘
```

### 1.4 Mỗi bước đọc gì, hỏi gì?

#### ① Alerting Overview

| Đọc gì | Hỏi gì |
|--------|--------|
| Active Alerts count | Có bao nhiêu alert đang firing? |
| Severity breakdown | Critical hay warning? |
| Alert timeline | Alert bắt đầu khi nào? Có correlate với deploy không? |
| Watchdog status | Alerting pipeline có hoạt động không? |

**Quyết định:** Severity quyết định urgency → Critical = hành động ngay, Warning = theo dõi.

#### ② Unified Overview

| Đọc gì | Hỏi gì |
|--------|--------|
| Service Health (RPS per service) | Service nào mất traffic? |
| Error Rate per service | Service nào đang lỗi? |
| P95 Latency | Service nào đang chậm? |
| Deployment annotations | Có deploy gần đây không? |

**Quyết định:** Xác định blast radius — 1 service hay nhiều service? Upstream hay downstream?

#### ③ App Performance (RED)

| Metric | Ý nghĩa | Ngưỡng tham khảo |
|--------|---------|------------------|
| **Rate** (req/s) | Throughput | So sánh với baseline bình thường |
| **Errors** (%) | Tỷ lệ lỗi | < 1% tốt, > 5% nghiêm trọng |
| **Duration** (P50/P95/P99) | Latency | P95 < 500ms, P99 < 1s |

**Đọc theo từng section:** Order Service → Payment → Notification → Inventory → End-to-End

#### ④ Tracing

| Đọc gì | Hỏi gì |
|--------|--------|
| Trace count & error traces | Bao nhiêu request lỗi? |
| Span duration breakdown | Span nào chiếm nhiều thời gian nhất? |
| Service dependency map | Request đi qua những service nào? |

**Kỹ thuật:** Filter theo `status=error`, sort by duration descending → tìm outlier.

#### ⑤ DB / Cache / Kafka

| Dashboard | Đọc gì |
|-----------|--------|
| DB Performance | Query duration, connection pool, slow queries |
| Cache Performance | Hit rate, latency, evictions |
| Kafka Overview | Consumer lag, produce rate, partition health |

---

## Part 2: Bài thực hành — Giả lập Incident

> **⚠️ Cảnh báo:** Tất cả thực hành trên lab environment. Không bao giờ chạy chaos experiments trên production mà không có safety controls.

### Nguyên tắc thực hành

1. **Steady state trước** — xác định baseline metrics trước khi inject failure
2. **Blast radius nhỏ** — bắt đầu với impact nhỏ nhất
3. **Rollback < 30s** — luôn có cách revert nhanh
4. **Một biến số** — chỉ thay đổi 1 thứ mỗi lần
5. **Ghi lại bài học** — mỗi experiment phải có learning summary

---

### 🧪 Experiment 1: Service Down (TargetDown alert)

**Giả thuyết:** Khi order-service bị stop, Alerting Overview sẽ hiển thị TargetDown alert critical trong 1 phút, Unified Overview sẽ thấy RPS drop về 0.

**Inject:**
```bash
# Trên applications VM
docker stop order-service
```

**Dashboard reading path:**
```
Alerting Overview → thấy TargetDown firing (severity: critical)
  → Unified Overview → Order Service RPS = 0, các service khác vẫn có traffic
    → App Performance → Order Service section: tất cả panel = no data
      → Kafka Overview → produce rate giảm (order-service không publish events)
```

**Quan sát kỳ vọng:**
- ① Alerting: `TargetDown` firing sau ~1 phút (cấu hình `for: 1m`)
- ② Unified: Order Service RPS gauge đỏ, Payment/Notification vẫn xanh
- ③ App Performance: Order section trống, nhưng Notification vẫn xử lý events cũ
- ⑤ Kafka: Produce rate = 0, consumer lag không tăng (không có event mới)

**Rollback:**
```bash
docker start order-service
```

**Bài học:** Phân biệt "service down" vs "service slow" — down = no data, slow = data có nhưng duration cao.

---

### 🧪 Experiment 2: Database Saturation (High Latency)

**Giả thuyết:** Khi DB bị lock, P95 latency sẽ tăng đột ngột, error rate sẽ tăng theo sau.

**Inject:**
```bash
# Tạo table lock trong 60s để tạo contention
docker exec postgres psql -U app -d orders -c "
  BEGIN;
  LOCK TABLE products IN ACCESS EXCLUSIVE MODE;
  SELECT pg_sleep(60);
  COMMIT;
"
```

**Dashboard reading path:**
```
App Performance → P95/P99 duration spike ở Order Service
  → DB Performance → connection pool active tăng, query duration tăng
    → Tracing → span "db.query" chiếm 90%+ thời gian
      → Alerting → HighLatencyP95 firing
```

**Rollback:** Lock tự release sau 60s, hoặc kill session:
```bash
docker exec postgres psql -U app -d orders -c "
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE state = 'active' AND query LIKE '%pg_sleep%';
"
```

---

### 🧪 Experiment 3: Kafka Consumer Lag (Notification Worker Slow)

**Giả thuyết:** Khi notification-worker bị freeze, Kafka consumer lag sẽ tăng, Alerting sẽ báo KafkaConsumerLagHigh.

**Inject:**
```bash
# Pause notification-worker (SIGSTOP — freeze process)
docker pause notification-worker

# Chạy load test để tạo events (Flash Sale hoặc Browse Heavy trên UI)
```

**Dashboard reading path:**
```
Kafka Overview → Consumer lag tăng liên tục cho notification-workers group
  → Alerting → KafkaConsumerLagHigh firing (lag > 100 trong 5m)
    → App Performance → Notification Worker: tất cả panel = stale/no new data
      → Unified Overview → Notification Worker error rate có thể tăng
```

**Rollback:**
```bash
docker unpause notification-worker
# Notification worker sẽ catch up — quan sát lag giảm dần
```

**Bài học:** Consumer lag là **leading indicator** — nó tăng TRƯỚC khi user thấy ảnh hưởng. Đây là lý do monitor lag quan trọng.

---

### 🧪 Experiment 4: Cascading Failure (Payment Service Down)

**Giả thuyết:** Khi payment-service down, order-service sẽ báo payment_error, notification-worker vẫn nhận events nhưng với status khác.

**Inject:**
```bash
docker stop payment-service
# Tạo vài orders qua UI
```

**Dashboard reading path:**
```
Unified Overview → Payment Service RPS = 0
  → App Performance → Order Service: orders_total{status="payment_error"} tăng
    → App Performance → Payment section: no data
      → Notification Worker: vẫn nhận events (order.created vẫn publish)
        → Kafka Overview → produce rate vẫn có, consume rate vẫn có
          → Tracing → trace chain bị đứt ở payment span (error)
```

**Bài học:** Cascading failure pattern — upstream service (order) ghi nhận lỗi nhưng không crash. Downstream (notification) vẫn hoạt động. Đây là **graceful degradation**.

**Rollback:**
```bash
docker start payment-service
```

---

### 🧪 Experiment 5: SLO Burn Rate (Sustained Error Rate)

**Giả thuyết:** Sustained errors sẽ trigger burn rate alerts khi error budget bị tiêu hao nhanh.

**Inject:**
```bash
# Stop payment-service → 100% orders sẽ có payment_error
docker stop payment-service

# Chạy load test (Flash Sale) — tạo nhiều failed orders
```

**Dashboard reading path:**
```
SLO Overview → API Gateway Availability gauge giảm
  → Error Budget Remaining giảm dần
    → Burn Rate chart tăng
      → Alerting → APIGatewayFastBurn hoặc APIGatewaySlowBurn firing
        → App Performance → xác định error source
```

**Bài học:** SLO burn rate alerts phát hiện vấn đề sớm hơn threshold alerts. Fast burn (14x) = sự cố nghiêm trọng. Slow burn (2x) = degradation âm thầm.

**Rollback:**
```bash
docker start payment-service
```

---

### 🧪 Experiment 6: Stock Depletion Deadlock (Logic Bug)

> Đây chính là incident thực tế đã xảy ra trong quá trình phát triển hệ thống này.

**Giả thuyết:** Khi stock = 0, nếu không có event flow để trigger restock, hệ thống rơi vào deadlock.

**Inject:**
```bash
docker exec postgres psql -U app -d orders -c "UPDATE products SET stock = 0;"
curl -X POST http://localhost:5001/process
```

**Dashboard reading path:**
```
App Performance → Order Service: inventory_checks{result="out_of_stock"} tăng
  → Order Service: orders_total{status="out_of_stock"} tăng
    → Inventory Worker → Auto-Restock Events = no data (deadlock!)
      → Kafka Overview → produce rate giảm (ít events vì orders fail)
```

**Bài học:** Đây là **design-level failure** — không phải infrastructure, không phải code bug, mà là missing event flow. Dashboard cho thấy triệu chứng nhưng root cause nằm ở architecture.

**Rollback:**
```bash
docker exec postgres psql -U app -d orders -c "UPDATE products SET stock = 100;"
```

---

### 🧪 Experiment 7: Memory Pressure (Container Resource Limit)

**Giả thuyết:** Khi container bị giới hạn memory, latency tăng → eventually OOMKilled.

**Inject:**
```bash
docker update --memory=64m --memory-swap=64m order-service
# Chạy load test nặng
```

**Dashboard reading path:**
```
Infrastructure → Docker Containers → memory usage tăng đến limit
  → App Performance → Order Service P95 tăng (GC pauses)
    → Alerting → HighMemoryUsage có thể firing
      → Docker Containers → restart count tăng nếu OOMKilled
```

**Rollback:**
```bash
docker update --memory=0 order-service  # remove limit
docker restart order-service
```

---

### 🧪 Experiment 8: DNS Cache Stale (Nginx Proxy Issue)

> Đây cũng là incident thực tế đã xảy ra trong quá trình phát triển hệ thống này.

**Giả thuyết:** Khi rebuild container, nginx giữ IP cũ → Connection refused.

**Inject:**
```bash
# Ghi nhận IP hiện tại
docker inspect inventory-worker --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# Rebuild (sẽ nhận IP mới)
docker compose up -d --build inventory-worker

# Kiểm tra IP mới — nếu khác IP cũ → web-ui sẽ báo DOWN
docker inspect inventory-worker --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

**Dashboard reading path:**
```
Web UI → Inventory Worker badge = DOWN (red)
  → Nhưng docker ps → container healthy
    → web-ui logs → "Connection refused" tới IP cũ
      → Không phải monitoring issue mà là networking issue
```

**Fix:** `docker restart web-ui` (reload nginx DNS)

**Bài học:** Dashboard có thể **misleading** — service thực sự healthy nhưng proxy layer không reach được. Cần cross-reference với container status.

---

## Part 3: Checklist sau mỗi Experiment

Sử dụng template sau cho mỗi bài thực hành:

```markdown
## Experiment: [Tên]
- [ ] Ghi baseline metrics trước khi inject
- [ ] Chụp screenshot dashboards trước/sau
- [ ] Alert nào đã firing? Sau bao lâu?
- [ ] Dashboard nào cho thấy root cause nhanh nhất?
- [ ] Dashboard nào misleading hoặc không hữu ích?
- [ ] Rollback thành công? Mất bao lâu để metrics recover?
- [ ] Bài học rút ra:
```

---

## Part 4: Thứ tự thực hành đề xuất

| Thứ tự | Experiment | Độ khó | Kỹ năng học được |
|--------|-----------|--------|-----------------|
| 1 | Service Down | ⭐ | Đọc alert cơ bản, phân biệt down vs slow |
| 2 | Cascading Failure | ⭐⭐ | Hiểu dependency chain, graceful degradation |
| 3 | Kafka Consumer Lag | ⭐⭐ | Leading vs lagging indicators |
| 4 | Stock Deadlock | ⭐⭐⭐ | Design-level failure, cross-dashboard correlation |
| 5 | DB Saturation | ⭐⭐⭐ | Resource bottleneck, USE method |
| 6 | SLO Burn Rate | ⭐⭐⭐ | Error budgets, burn rate math |
| 7 | DNS Cache | ⭐⭐⭐⭐ | Misleading dashboards, networking |
| 8 | Memory Pressure | ⭐⭐⭐⭐ | Infrastructure monitoring, predictive alerts |
