# 📊 Incident Simulation Guide

## Mục tiêu

Hướng dẫn đọc dashboard theo chuẩn production-grade bằng phương pháp **Incident Flow** — đi theo luồng sự cố thực tế thay vì đọc từng dashboard rời rạc. Kèm 12 bài thực hành giả lập incident trên hệ thống hiện tại.

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

### 1.5 Ví dụ thực tế: Đọc Incident Flow end-to-end

> Ví dụ dưới đây mô phỏng 1 incident thực tế, đi qua đủ 5 bước Incident Flow. Đọc trước khi chạy experiments để hình dung cách áp dụng.

**Tình huống:** Thứ 2 sáng, nhận alert `APIGatewayLatencyFastBurn` (critical). Khách phàn nàn đặt hàng mất 3-5 giây, bình thường ~500ms.

#### ① Alerting Overview

| Quan sát | Giá trị |
|----------|---------|
| Alert firing | `APIGatewayLatencyFastBurn` — critical |
| Các alert khác | Chỉ có Watchdog (bình thường) |

→ **Quyết định:** Chỉ có latency alert, không có availability → service **không down**, chỉ **chậm**.

#### ② Unified Overview

| Metric | Giá trị | Bình thường |
|--------|---------|-------------|
| RPS | 45 req/s | 40 req/s ✅ |
| Error Rate | 0.3% | < 1% ✅ |
| **P95 Latency** | **3.2s** | **500ms** 🔴 |

→ **Quyết định:** Không phải traffic surge (RPS bình thường), không phải lỗi logic (error rate thấp). Đâu đó bị nghẽn.

#### ③ App Performance (RED)

| Service | P95 Latency | Bình thường |
|---------|-------------|-------------|
| api-gateway | 3.2s | 500ms 🔴 |
| order-service | 3.1s | 400ms 🔴 |
| payment-service | 200ms | 180ms ✅ |

→ **Phát hiện:** Payment bình thường — bottleneck nằm trong order-service, không phải downstream.

#### ④ Tracing — Trace Investigation

Mở panel **Slow Requests (> 500ms)** → click 1 trace có duration 3.2s → đọc waterfall:

```
api-gateway POST /order ─────────────────── 3.2s
  └─ order-service POST /process ────────── 3.1s
       ├─ get_product_info ──── 2.13ms   ✅ nhanh
       ├─ check_inventory ───── 1.12ms   ✅ nhanh
       ├─ insert_order ──────── 2.8s     🔴 87% tổng thời gian!
       ├─ update_stock ──────── 18ms     ✅ nhanh
       └─ request_payment ───── 200ms    ✅ nhanh
```

→ **Phát hiện:** `insert_order` (DB write) chiếm 2.8s / 3.2s = **87.5%** tổng thời gian.

> **Kỹ thuật đọc trace:** Tìm thanh ngang dài nhất trong waterfall → đó là bottleneck. Tính tỷ lệ % so với tổng duration để xác nhận.

#### ⑤ DB Performance

| Metric | Giá trị | Bình thường |
|--------|---------|-------------|
| Connection pool active | 10/10 | 2-3/10 🔴 Pool đầy |
| Avg query duration | 2.5s | 5ms 🔴 Gấp 500 lần |
| Slow queries | 38 | 0 🔴 |

→ **Root cause:** DB bị saturated. Pool đầy vì gthread workers (2×8 = 16 threads) cùng lấy connection, vượt quá pool max (10). Kiểm tra Loki logs → PostgreSQL autovacuum đang chạy trên bảng `orders`, lock table → mọi query phải chờ.

#### Tổng kết flow

```
Alert (Latency burn rate)
  → Unified (P95 tăng 6x, error OK, RPS OK)
    → App Performance (order-service chậm, payment OK)
      → Trace waterfall (insert_order = 87% thời gian)
        → DB Performance (pool đầy, query chậm 500x)
          → Logs (autovacuum đang lock table)
```

> **Bài học:** Không dashboard nào đơn lẻ cho đủ thông tin. Mỗi bước **thu hẹp phạm vi** cho đến khi tìm root cause. Đặc biệt, bước ④ Tracing giúp **pinpoint chính xác operation nào** trong code gây chậm — thay vì đoán.

---

## Part 2: Bài thực hành — Giả lập Incident

> **⚠️ Cảnh báo:** Tất cả thực hành trên lab environment. Không bao giờ chạy chaos experiments trên production mà không có safety controls.

### Nguyên tắc thực hành

1. **Steady state trước** — xác định baseline metrics trước khi inject failure
2. **Blast radius nhỏ** — bắt đầu với impact nhỏ nhất
3. **Rollback < 30s** — luôn có cách revert nhanh
4. **Một biến số** — chỉ thay đổi 1 thứ mỗi lần
5. **Ghi lại bài học** — mỗi experiment phải có learning summary

### Cách đo Baseline (bắt buộc trước mỗi Experiment)

> **Tại sao:** Không có baseline = không biết metrics thay đổi bao nhiêu. "P95 = 3s" vô nghĩa nếu không biết bình thường là 400ms hay 2s.

**Bước 1:** Đảm bảo hệ thống stable — không có alert firing, không có traffic-gen đang chạy.

**Bước 2:** Chạy traffic nhẹ để tạo baseline data:
```bash
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 60}'
```

**Bước 3:** Trong khi traffic chạy, mở từng dashboard và ghi lại giá trị:

| Dashboard | Metric | Đọc ở panel nào | Baseline tham khảo |
|-----------|--------|-----------------|-------------------|
| Unified Overview | RPS per service | Service Health | api-gateway ~2 req/s |
| Unified Overview | Error rate | Service Health | < 1% |
| Unified Overview | P95 latency | Service Health | 300-600ms |
| App Performance | P50 / P95 / P99 | Duration panels | P50 ~200ms, P99 ~800ms |
| DB Performance | Connection pool active | Pool panel | 1-3/10 |
| DB Performance | Avg query duration | Query panel | 1-10ms |
| Cache Performance | Hit rate | Hit Rate panel | > 80% |
| Cache Performance | Latency | Latency panel | < 5ms |
| Kafka Overview | Consumer lag | Lag panel | 0-5 |
| Infrastructure | CPU usage | Node Exporter | < 30% |
| Infrastructure | Memory usage | Node Exporter | < 60% |
| Alerting | Active alerts | Alert count | Chỉ Watchdog |

**Bước 4:** Ghi timestamp bắt đầu inject failure (dùng cho tính MTTD sau).

> **Mẹo:** Dùng Grafana annotation (nhấn Ctrl+Click trên chart → Add annotation) để đánh dấu thời điểm inject — giúp so sánh trước/sau dễ hơn.

---

### 🧪 Experiment 1: Service Down (Health Check Failed)

> **📋 Runbook:** [RB-01 TargetDown](INCIDENT_RUNBOOK.md#-rb-01-targetdown) · [RB-23 ServiceNoTraces](INCIDENT_RUNBOOK.md#-rb-23-servicenotraces_)

**Giả thuyết:** Khi order-service bị stop, Blackbox Exporter sẽ detect health check failure → `ServiceHealthCheckFailed` alert critical trong 1 phút, không phụ thuộc vào traffic.

> **Production context:** Trong production, service down detection dùng **active probing** (Blackbox Exporter probe /health/live mỗi 15s) thay vì dựa vào span metrics — vì span metrics cần traffic để hoạt động.

**Inject:**
```bash
# Trên applications VM
docker stop order-service
```

**Dashboard reading path:**
```
Alerting Overview → ServiceHealthCheckFailed firing (severity: critical)
  → Instance: http://192.168.100.57:5001/health/live
    → Unified Overview → Order Service RPS giảm/mất (nếu có traffic)
      → App Performance → Order Service section: no data
        → Kafka Overview → produce rate giảm (không publish events mới)
```

**Quan sát kỳ vọng:**
- ① Alerting: `ServiceHealthCheckFailed` firing sau ~1 phút (cấu hình `for: 1m`)
- ① Alerting: Nếu traffic-gen đang chạy → `ServiceNoTraces_OrderService` cũng firing sau ~5 phút
- ② Unified: Order Service RPS drop (nếu có traffic), các service khác vẫn hoạt động
- ③ App Performance: Order section trống, Notification vẫn xử lý events cũ
- ⑤ Kafka: Produce rate = 0, consumer lag không tăng (không có event mới)

> **Lưu ý:** `TargetDown` (up == 0) **không** firing trong experiment này vì Prometheus không scrape order-service trực tiếp — metrics đi qua OTel Collector (vẫn healthy). Đây là lý do cần Blackbox Exporter.

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Down vs Slow:** Service down hiển thị thế nào trên dashboard? (no data, RPS = 0). Khác gì service slow? (data vẫn có, nhưng duration cao)
2. **Blast radius:** order-service chết → service nào vẫn hoạt động bình thường? Tại sao payment-service không bị ảnh hưởng?
3. **2 lớp monitoring:** Tại sao `TargetDown` không firing mà `ServiceHealthCheckFailed` lại firing? Nếu 3 giờ sáng không có traffic, lớp monitoring nào detect được?
4. **Ứng dụng production:** Nếu bạn là on-call engineer nhận alert `ServiceHealthCheckFailed` lúc 2 giờ sáng, 3 bước đầu tiên bạn làm là gì? (Gợi ý: xem RB-24)

**Rollback:**
```bash
docker start order-service
```

**Bài học:** Phân biệt 2 lớp monitoring:
- **Lớp 1 — Service có sống không?** → Blackbox Exporter (active probing, không cần traffic)
- **Lớp 2 — Service có hoạt động đúng không?** → Span metrics (error rate, latency, cần traffic)

---

### 🧪 Experiment 2: Database Saturation (High Latency)

> **📋 Runbook:** [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md#-rb-22-highlatencyp95) · [RB-21 HighErrorRate](INCIDENT_RUNBOOK.md#-rb-21-higherrorrate) · [RB-12 LatencyFastBurn](INCIDENT_RUNBOOK.md#-rb-12-apigatewaylatencyfastburn)

**Giả thuyết:** Khi DB bị lock, P95 latency sẽ tăng đột ngột, connection pool sẽ bị exhaust, error rate sẽ tăng theo sau.

> ⚠️ **QUAN TRỌNG:** Experiment này cần **3 terminal chạy song song**. Table lock chỉ gây contention khi
> có traffic đang cố query table `products`. Nếu chạy lock mà không có traffic → dashboard sẽ không có data.

> **Tại sao cần rate cao?** API Gateway và Order Service chạy **gthread workers** (2 workers × 8 threads = 16 concurrent requests).
> DB connection pool max = 10. Với rate đủ cao, 16 threads cùng cố lấy connection → pool 10/10 đầy →
> 6 threads còn lại phải **queue chờ** `getconn()` → latency stacking → timeout → errors cascade.
> Với rate thấp (5 req/s), requests tuần tự nên pool chỉ nhích lên 1-2 — không thể hiện được saturation.

**Inject (3 terminals song song):**

```bash
# Terminal 1: Flush product cache để request phải query DB ngay lập tức
# (Nếu cache warm, browse requests sẽ hit cache → bypass DB → không thấy contention)
docker exec redis redis-cli DEL "product:catalog"
```

```bash
# Terminal 2: Tạo table lock trong 90s (command này sẽ block 90 giây)
docker exec postgres psql -U app -d orders -c "
  BEGIN;
  LOCK TABLE products IN ACCESS EXCLUSIVE MODE;
  SELECT pg_sleep(90);
  COMMIT;
"
```

```bash
# Terminal 3: ĐỒNG THỜI — tạo traffic rate cao để gây contention
# Rate 20 = ~20 req/s, trong đó ~70% gọi /products (browse_heavy + browse_then_buy)
# → ~14 concurrent DB queries bị block → pool 10/10 exhaust
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "browse_heavy", "rate": 20, "duration": 120}'
```

> **Timing:** lock=90s, traffic=120s → bạn sẽ thấy 3 phases trên dashboard:
> 1. **Phase contention** (0-90s): pool đầy, latency spike, errors cascade
> 2. **Phase recovery** (90-120s): lock release → pool giảm, latency trở lại, backlog xử lý
> 3. **Phase steady** (sau 120s): traffic stop → metrics stabilize

> **Cache-aside interaction:** Order Service dùng Redis cache (TTL=60s) cho product catalog.
> Nếu cache warm → browse requests trả về từ cache, không query DB → không bị ảnh hưởng bởi lock.
> Bước flush cache ở Terminal 1 đảm bảo request đầu tiên phải query DB → block → các requests
> sau cũng phải query DB (vì cache chưa được set lại) → tạo contention thực sự.

**Dashboard reading path:**
```
App Performance → P95/P99 duration spike ở Order Service (từ ~400ms lên 5-30s)
  → DB Performance → connection pool active tăng lên 8-10/10 (pool gần đầy hoặc đầy)
    → DB Performance → query duration spike (SELECT bị block hàng giây thay vì ms)
      → Tracing → mở 1 slow trace → span get_product_catalog chiếm 90%+ thời gian
        → Bên trong có child span psycopg2 auto-instrumented (SELECT) bị block bởi lock
          → Alerting → HighLatencyP95 firing, sau đó HighErrorRate khi requests timeout
```

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **USE method:** DB saturation thể hiện ở metric nào? (connection pool utilization, query duration). Đây là U, S, hay E trong USE?
2. **Pool exhaustion:** Tại sao pool active tăng lên 8-10 thay vì chỉ 1-2? (vì gthread cho phép 8 threads/worker xử lý concurrent → 8 threads cùng lấy connection → pool đầy). Với sync workers (1 request/worker), pool chỉ bao giờ lên tối đa = số workers — đây là kiến thức quan trọng khi sizing connection pool.
3. **Trace reading:** Mở 1 slow trace → span nào chiếm % lớn nhất? Span đó thuộc service nào?
4. **Leading vs lagging:** Alert nào firing đầu tiên? `HighLatencyP95` hay `HighErrorRate`? Tại sao? (latency tăng trước → connection queue → timeout → error)
5. **Cache interaction:** Nếu KHÔNG flush cache trước khi lock, experiment sẽ khác thế nào? (browse requests hit cache → không bị ảnh hưởng → pool không đầy). Đây là lý do cache-aside pattern giúp **giảm blast radius** của DB issues.
6. **Ứng dụng production:** Khách hàng phàn nàn "đặt hàng chậm" — bạn mở dashboard nào đầu tiên? Tại sao không mở trực tiếp DB dashboard?
7. **Connection pool sizing:** Với 2 workers × 8 threads = 16 concurrent, nhưng pool max = 10. Điều gì xảy ra với 6 requests vượt quá pool? (chờ `getconn()` → thêm latency → có thể timeout). Trong production, công thức sizing pool là gì?

**Rollback:** Lock tự release sau 90s, hoặc kill session:
```bash
docker exec postgres psql -U app -d orders -c "
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE state = 'active' AND query LIKE '%pg_sleep%';
"
```

---

### 🧪 Experiment 3: Kafka Consumer Lag (Notification Worker Slow)

> **📋 Runbook:** [RB-16 ConsumerLagHigh](INCIDENT_RUNBOOK.md#-rb-16-kafkaconsumerlaghigh-lag--100) · [RB-17 ConsumerLagCritical](INCIDENT_RUNBOOK.md#-rb-17-kafkaconsumerlagcritical-lag--1000) · [RB-18 ConsumerGroupDown](INCIDENT_RUNBOOK.md#-rb-18-kafkaconsumergroupdown)

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

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Leading indicator:** Consumer lag bắt đầu tăng bao lâu trước khi user thấy ảnh hưởng? Tại sao gọi nó là "leading"?
2. **Pause vs Stop:** `docker pause` khác `docker stop` thế nào trên dashboard? (pause: container vẫn "running" nhưng frozen, không có restart count)
3. **Catch-up behavior:** Sau khi unpause, lag giảm ngay hay giảm dần? Tại sao? Mất bao lâu để về 0?
4. **Ứng dụng production:** Notification bị delay 5 phút — khách hàng chưa bị ảnh hưởng trực tiếp nhưng SLA email notification là 2 phút. Bạn cần page on-call hay tạo ticket?

**Rollback:**
```bash
docker unpause notification-worker
# Notification worker sẽ catch up — quan sát lag giảm dần
```

**Bài học:** Consumer lag là **leading indicator** — nó tăng TRƯỚC khi user thấy ảnh hưởng. Đây là lý do monitor lag quan trọng.

---

### 🧪 Experiment 4: Cascading Failure (Payment Service Down)

> **📋 Runbook:** [RB-01 TargetDown](INCIDENT_RUNBOOK.md#-rb-01-targetdown) · [RB-10 PaymentFastBurn](INCIDENT_RUNBOOK.md#-rb-10-paymentfastburn) · [RB-08 APIGatewayFastBurn](INCIDENT_RUNBOOK.md#-rb-08-apigatewayfastburn)

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

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Cascade pattern:** Payment chết → order-service phản ứng thế nào? Crash theo hay trả error rồi tiếp tục? Đây gọi là gì? (graceful degradation)
2. **Trace chain:** Mở 1 trace lúc payment down → span payment bị error → nhưng order-service span status là gì? (error hay ok?)
3. **Kafka behavior:** produce rate thay đổi thế nào? Tại sao notification-worker vẫn hoạt động dù payment chết?
4. **SLO impact:** Burn rate của API Gateway vs Payment — cái nào tăng nhanh hơn? Tại sao?
5. **Ứng dụng production:** Payment gateway (Stripe/VNPay) bị sự cố — bạn nên stop nhận order mới hay vẫn nhận và retry sau?

**Bài học:** Cascading failure pattern — upstream service (order) ghi nhận lỗi nhưng không crash. Downstream (notification) vẫn hoạt động. Đây là **graceful degradation**.

**Rollback:**
```bash
docker start payment-service
```

---

### 📖 Experiment 5: SLO Burn Rate Deep Dive (Learning Exercise)

> **📋 Runbook:** [RB-08→13 (tất cả SLO Burn Rate)](INCIDENT_RUNBOOK.md#part-2-slo-burn-rate-alerts)

> **Loại:** Learning exercise — không inject failure mới. Sử dụng data từ Experiment 2 và 4.

**Mục tiêu:** Hiểu sâu burn rate math, đọc burn rate dashboard, và biết cách phản ứng theo team size.

#### 5.1 — Theory: Error Budget & Burn Rate

**Bước 1: Tính Error Budget**

Hệ thống có 3 SLO. Tính error budget cho mỗi SLO:

| SLO | Target | Error Budget (30 ngày) |
|-----|--------|----------------------|
| API Gateway Availability | 99.5% | 0.5% × 30d × 24h × 60m = **216 phút** |
| Payment Success Rate | 99.0% | 1.0% × 30d × 24h × 60m = **432 phút** |
| API Gateway Latency | 95% requests < 500ms | 5% × 30d × 24h × 60m = **2160 phút** |

> **Nhận xét:** Latency SLO có budget lớn hơn nhiều (5% vs 0.5%). Đây là thiết kế có chủ ý — latency degradation thường ít nghiêm trọng hơn complete failure.

**Bước 2: Hiểu Burn Rate**

```
Burn Rate = error_rate_thực_tế / error_rate_cho_phép

  1x  = đốt đều, hết budget đúng cuối tháng (bình thường)
  3x  = đốt gấp 3, hết budget sau 10 ngày
  14.4x = đốt cực nhanh, hết budget sau ~2 ngày
```

**Bước 3: Tại sao 14.4x và 3x?**

Con số này được tính ngược từ yêu cầu phát hiện:

| Severity | Mục tiêu phát hiện | Budget tiêu trước khi phát hiện | Burn Rate |
|----------|-------------------|-------------------------------|-----------|
| **Critical (page)** | Trong 1 giờ | 2% budget | 14.4x |
| **Warning (ticket)** | Trong 6 giờ | 5% budget | 3x |

**Bước 4: Tại sao Multi-Window?**

Yêu cầu **cả 2 windows** vượt ngưỡng mới alert:
- **Window ngắn** (5m/30m): xác nhận "đang xảy ra ngay bây giờ"
- **Window dài** (1h/6h): xác nhận "không phải spike thoáng qua"

| Alert | Window ngắn | Window dài | Cả 2 vượt? | Kết quả |
|-------|------------|-----------|-----------|---------|
| Spike 1 phút rồi hết | 5m > 14.4x ✅ | 1h < 14.4x ❌ | Không | Không alert ✅ |
| Service sập 15 phút | 5m > 14.4x ✅ | 1h > 14.4x ✅ | Có | PAGE! 🔴 |
| Chậm nhẹ 6 giờ | 30m > 3x ✅ | 6h > 3x ✅ | Có | Ticket 🟡 |

#### 5.2 — Thực hành: Đọc Burn Rate Dashboard

**Prerequisite:** Chạy Experiment 2 (DB Saturation) hoặc Experiment 4 (Cascading Failure) trước.

**Sau khi inject xong, mở SLO Overview dashboard và trả lời:**

1. Gauge "API Gateway Availability" hiển thị bao nhiêu? So với SLO target 99.5%?
2. Burn Rate chart: line "Fast (5m)" có vượt đường đỏ 14.4x không?
3. Burn Rate chart: line "Fast (1h)" có vượt 14.4x không? (nếu chưa → multi-window đang bảo vệ bạn khỏi false alert)
4. Error Budget gauge giảm bao nhiêu? Tính thủ công: `error_rate × thời_gian_lỗi / 216 phút`
5. **Latency Compliance** panel: giá trị bao nhiêu? So với SLO target 95%?
6. **Latency Burn Rate**: có khác biệt gì so với Availability Burn Rate không?

> **Bài học quan trọng:** Trong Experiment 4 (stop payment), Availability burn rate sẽ spike nhưng Latency burn rate có thể **bình thường** — vì requests fail nhanh (error ngay, không chậm). Đây là lý do cần **cả 2 loại SLO**.

#### 5.3 — Tính toán thực tế

**Bài tập:** Sau khi chạy Experiment 2 được 15 phút với error rate ~10%:

```
Error Budget = 216 phút
Error rate = 10%
Thời gian = 15 phút

Lưu ý: Error Budget tính theo request-based, không phải time-based!
Error minutes tiêu thụ = 15 phút × 10% = 1.5 phút
Budget consumed = 1.5 / 216 × 100 = 0.694%

Kiểm chứng bằng burn rate:
Burn rate = 10% / 0.5% = 20x
Budget consumed = 20 × (15 / 43200) = 0.694% ✅
```

**Sai lầm phổ biến:** Tính 15/216 = 6.94% — chỉ đúng khi 100% requests lỗi (hoàn toàn sập). Với 10% error rate, phải nhân với 10%.

#### 5.4 — Operation Playbook theo Team Size

**Khi Burn Rate Alert firing, ai làm gì?**

**Solo / Startup (1-3 người):**
```
Fast Burn (14.4x) firing:
  1. Nhận alert qua Telegram/Slack
  2. Mở SLO Overview → xác nhận burn rate thực sự cao
  3. Mở App Performance → xác định service nào lỗi
  4. Fix hoặc rollback
  5. Viết post-mortem ngắn (3 dòng: gì xảy ra, tại sao, fix gì)

Slow Burn (3x) firing:
  1. Tạo task/issue
  2. Xử lý trong giờ làm việc (không cần phản ứng ngay)
```

**Team vừa (5-10 người):**
```
Fast Burn (14.4x) firing:
  1. On-call engineer nhận page
  2. Mở SLO Overview → xác nhận severity
  3. Thông báo team lead nếu burn rate > 14.4x kéo dài > 15 phút
  4. Mở App Performance → drill down root cause
  5. Fix hoặc rollback
  6. Handoff nếu hết shift
  7. Post-mortem meeting trong 48 giờ

Slow Burn (3x) firing:
  1. On-call tạo ticket với priority P2
  2. Assign cho team phù hợp (backend/infra/platform)
  3. Review trong standup sáng hôm sau
  4. Fix trong sprint hiện tại

Error Budget review (hàng tuần):
  - Budget < 50% → freeze feature releases, focus reliability
  - Budget < 25% → engineering manager escalation
```

**Team lớn (10+ người, có SRE team riêng):**
```
Fast Burn (14.4x) firing:
  1. On-call SRE nhận page → ack trong 5 phút
  2. Mở Incident channel (Slack #incident-YYYY-MM-DD)
  3. Assign Incident Commander (IC)
  4. IC coordinates: SRE fix, Comms update status page
  5. Fix/rollback → monitor 30 phút → resolve
  6. Blameless post-mortem trong 72 giờ

Slow Burn (3x) firing:
  1. Auto-create Jira ticket với context (burn rate, SLO, window)
  2. Triage trong SRE weekly review
  3. Assign action items với deadline

Error Budget policy:
  - Budget > 50%  → product team tự quyết release
  - Budget 25-50% → cần SRE approval cho risky changes
  - Budget < 25%  → release freeze, mandatory reliability sprint
  - Budget = 0%   → VP Engineering notified, full freeze
```

#### 5.5 — Checklist tự đánh giá

```markdown
## Sau Experiment 5, tôi có thể:
- [ ] Tính error budget từ SLO target
- [ ] Giải thích tại sao 14.4x và 3x (không cần nhớ số, hiểu logic)
- [ ] Phân biệt Availability burn rate vs Latency burn rate
- [ ] Đọc burn rate chart: biết khi nào cần page vs ticket
- [ ] Tính budget consumed từ error rate + thời gian
- [ ] Giải thích multi-window cho đồng nghiệp (tại sao cần 2 windows)
```

**Rollback:** Không cần — exercise này dùng data từ experiments khác.

---

### 🧪 Experiment 6: Stock Depletion Deadlock (Logic Bug)

> **📋 Runbook:** [RB-21 HighErrorRate](INCIDENT_RUNBOOK.md#-rb-21-higherrorrate) (alert có thể firing do order errors tăng)

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

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **3 loại failure:** Phân biệt infrastructure failure (Exp 1), code bug, và design-level failure. Experiment này thuộc loại nào? Tại sao?
2. **Dashboard limitation:** Dashboard nào cho thấy triệu chứng rõ nhất? Dashboard nào **không giúp gì** trong trường hợp này? Tại sao?
3. **Missing event flow:** Vẽ sơ đồ event flow bình thường: `order.created → payment → notification → restock check`. Khi stock = 0, chuỗi bị đứt ở đâu?
4. **Monitoring gap:** Bạn có thể viết alert rule nào để detect trạng thái deadlock này không? (Gợi ý: `orders_total{status="out_of_stock"} > X` kết hợp `restock_events_total == 0`)
5. **Ứng dụng production:** Team PM báo "không ai đặt hàng được" nhưng tất cả infrastructure metrics đều xanh — bạn investigate thế nào?

**Bài học:** Đây là **design-level failure** — không phải infrastructure, không phải code bug, mà là missing event flow. Dashboard cho thấy triệu chứng nhưng root cause nằm ở architecture.

**Rollback:**
```bash
docker exec postgres psql -U app -d orders -c "UPDATE products SET stock = 100;"
```

---

### 🧪 Experiment 7: Memory Pressure (Container Resource Limit)

> **📋 Runbook:** [RB-03 HighMemoryUsage](INCIDENT_RUNBOOK.md#-rb-03-highmemoryusage) · [RB-06 MemoryWillExhaust](INCIDENT_RUNBOOK.md#-rb-06-memorywillexhaustin2hours) · [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md#-rb-22-highlatencyp95)

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

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **USE method:** Memory pressure là U (Utilization), S (Saturation), hay E (Errors)? Khi nào nó chuyển từ Saturation sang Errors? (GC pauses → OOMKilled)
2. **Predictive alerting:** `predict_linear()` dự đoán memory exhaustion — nó firing bao lâu trước khi OOM thực sự xảy ra? Giá trị này hữu ích thế nào lúc 3 giờ sáng?
3. **Cascading effect:** Memory pressure ảnh hưởng latency thế nào? Tại sao P95 tăng trước P50? (GC pauses ảnh hưởng tail latency trước)
4. **Container restart:** OOMKilled container tự restart → metrics có bị mất không? Làm sao phân biệt "service healthy sau restart" vs "service đang flapping"?
5. **Ứng dụng production:** Service bị OOMKilled 3 lần trong 1 giờ — bạn tăng memory limit hay investigate memory leak? Cách quyết định?

**Rollback:**
```bash
docker update --memory=0 order-service  # remove limit
docker restart order-service
```

---

### 🧪 Experiment 8: DNS Cache Stale (Nginx Proxy Issue)

> **📋 Runbook:** Không có alert tương ứng — đây là networking issue mà monitoring không detect được. Cần manual investigation.

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

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Monitoring blind spot:** Tại sao Prometheus/Blackbox Exporter không detect được vấn đề này? (Gợi ý: probe đi thẳng tới service, không qua nginx proxy)
2. **Misleading dashboard:** Web UI báo DOWN nhưng `docker ps` báo healthy — bạn tin cái nào? Cách cross-reference để xác nhận?
3. **DNS in Docker:** Container IP thay đổi khi nào? Tại sao nginx cache DNS lại gây vấn đề? Giải pháp production là gì? (resolver, service mesh)
4. **Incident classification:** Đây là SEV mấy theo incident-runbook-templates? (SEV3-4: service chạy, chỉ 1 proxy path bị ảnh hưởng)
5. **Ứng dụng production:** Sau deploy mới, 1 trong 5 service báo DOWN trên status page nhưng health check vẫn pass — nguyên nhân có thể là gì ngoài DNS cache?

**Bài học:** Dashboard có thể **misleading** — service thực sự healthy nhưng proxy layer không reach được. Cần cross-reference với container status.

---

### 🧪 Experiment 9: Phantom Alert — SLO Burn Rate khi không có Traffic

> **📋 Runbook:** [RB-08→13 (SLO Burn Rate)](INCIDENT_RUNBOOK.md#part-2-slo-burn-rate-alerts)

> Đây là incident thực tế đã xảy ra trong lab này — `APIGatewayFastBurn` firing lúc nửa đêm dù không có user traffic.

**Giả thuyết:** Sau khi traffic-gen chạy xong (có errors), SLO burn rate alert sẽ tiếp tục firing dù không còn traffic mới — vì `rate()` không thể "dilute" error rate khi `total = 0`.

**Inject:**
```bash
# Bước 1: Chạy traffic-gen với scenario có lỗi (ví dụ: stop payment trước)
docker stop payment-service
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 60}'

# Bước 2: Chờ traffic-gen chạy xong (60s)
# Bước 3: Start lại payment-service (fix incident)
docker start payment-service

# Bước 4: KHÔNG chạy traffic mới — chờ và quan sát alert
```

**Dashboard reading path:**
```
Alerting Overview → APIGatewayFastBurn firing (critical)
  → SLO Overview → Availability gauge < 99.5% (từ data cũ)
    → Unified Overview → tất cả RPS = 0 (không traffic)
      → App Performance → error rate "đóng băng" ở giá trị cuối
        → Tracing → không có trace mới
```

**Quan sát kỳ vọng:**
- Alert firing **dù incident đã được fix** (payment-service đã start lại)
- Dashboard hiển thị error rate từ lần chạy cuối — không tự reset về 0
- Không có trace mới để investigate — 3 pillars thiếu 2 (traces + logs trống)
- Alert chỉ resolve khi có **traffic mới thành công** để "dilute" error rate

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Stale metrics:** Tại sao `rate(errors[1h]) / rate(total[1h])` vẫn cao khi không có traffic? `0/0` trả về gì trong PromQL?
2. **Alert lifecycle:** Alert firing → incident fixed → nhưng alert không resolve. Trong production, on-call engineer nên làm gì? (silence alert + ghi chú? hay chạy synthetic traffic?)
3. **Root cause của phantom alert:** Vấn đề nằm ở alert rule hay ở bản chất của rate-based metrics?
4. **Production fix:** Viết lại alert rule thêm điều kiện gì để tránh phantom alert? (Gợi ý: `rate(total[5m]) > 0`)
5. **Alert fatigue:** Nếu team bắt đầu ignore SLO alerts vì "lại phantom alert" — hậu quả là gì khi incident thật xảy ra?

**Ví dụ production tương tự:**

> Công ty e-commerce, service `payment-webhook` nhận callback từ Stripe. Ban đêm (0h-6h) chỉ ~5-10 requests/giờ. Deploy lúc 21:00 có bug → 3 webhooks fail → error rate 100% → burn rate 200x. Rollback xong 21:10 nhưng alert firing đến 02:00 sáng (5 tiếng!) vì không có webhook mới. On-call bị đánh thức 2 lần cho incident đã fix.

**Fix trong alert rule:**
```yaml
# Thêm traffic guard — chỉ alert khi CÓ traffic
- alert: APIGatewayFastBurn
  expr: |
    slo:api_gateway_availability:burn_rate_1h > 14.4
    and slo:api_gateway_availability:burn_rate_5m > 14.4
    and rate(traces_spanmetrics_calls_total{service_name="api-gateway"}[5m]) > 0
```

**Rollback:** Không cần — đây là learning exercise.

**Bài học:** SLO burn rate alerts cần **traffic guard** (`rate(total) > 0`) cho low-traffic services. Không có traffic = không đủ data để tính burn rate chính xác.

---

### 🧪 Experiment 10: Timezone Trap — Đọc sai Dashboard do Timezone

> **📋 Runbook:** Không có alert tương ứng — đây là human error trong incident investigation, không phải system issue.

> Đây là incident thực tế đã xảy ra khi investigate alert trong lab này — Grafana browser timezone (UTC+7) ≠ server timezone (UTC) → đọc sai time window → investigate sai khoảng thời gian.

**Giả thuyết:** Khi Grafana timezone khác server timezone, on-call engineer sẽ suy luận sai về thời điểm xảy ra incident.

**Inject:**
```bash
# Không inject failure — thay đổi Grafana timezone
# 1. Mở Grafana → Profile → Preferences → Timezone
# 2. Đổi từ UTC sang "Browser Time" (hoặc UTC+7)
# 3. Mở bất kỳ dashboard nào và đọc time range
```

**Bẫy cần nhận biết:**

| Grafana hiển thị | Server (UTC) | Bạn nghĩ | Thực tế |
|-----------------|-------------|-----------|---------|
| 00:00 - 08:00 (UTC+7) | 17:00 - 01:00 UTC | "Sáng nay 0h-8h" | "Chiều/tối hôm qua" |
| Alert lúc 02:00 (UTC+7) | 19:00 UTC hôm trước | "2 giờ sáng" | "7 giờ tối" |
| Traffic drop lúc 07:00 (UTC+7) | 00:00 UTC | "7 giờ sáng nay" | "Nửa đêm" |

**Ví dụ cụ thể từ lab này:**

```
Tình huống: Alert "APIGatewayFastBurn" firing
Dashboard time picker: "2026-05-19 00:00:00 to 07:59:59"
Availability gauge: 92.4%

Suy luận SAI (không biết timezone):
  "Sáng nay 0h-8h, hệ thống availability 92.4%"
  → Tìm incident trong khoảng 0h-8h sáng nay

Suy luận ĐÚNG (biết timezone UTC+7):
  Dashboard = 00:00-08:00 UTC+7 = 17:00-01:00 UTC
  → Tìm incident trong khoảng 5PM-1AM hôm qua/nay (UTC)
  → Traffic-gen chạy lúc 14:40 UTC+7 (trước window 9 tiếng!)
```

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Timezone awareness:** Grafana timezone setting ở đâu? Cách kiểm tra nhanh timezone đang dùng?
2. **UTC convention:** Tại sao production teams thường thống nhất dùng UTC cho monitoring? Khi nào dùng local time có lợi?
3. **Cross-reference:** Khi đọc dashboard time range, bạn cần cross-reference với timestamp nào? (server logs, docker logs, alert firing time — tất cả đều dùng UTC)
4. **Incident impact:** Timezone sai có thể gây sai lệch investigation bao lâu? (Trong ví dụ này: tìm sai 9 tiếng)
5. **Team practice:** Nếu team có người ở nhiều timezone (VN, US, EU), cách nào tránh nhầm lẫn khi handoff incident?

**Best practice:**

```
① Grafana: set timezone = UTC cho tất cả monitoring dashboards
② Docker: đảm bảo host timezone = UTC (timedatectl set-timezone UTC)
③ Logs: luôn log timestamps ở UTC (ISO 8601: 2026-05-19T03:00:00Z)
④ Team: quy ước "nói giờ UTC khi discuss incident" — "incident lúc 17:00Z"
```

**Rollback:** Đổi Grafana timezone về UTC: Profile → Preferences → Timezone → UTC.

**Bài học:** Timezone mismatch là **human error phổ biến nhất** trong incident investigation. Chỉ cần 1 người đọc sai timezone → toàn bộ timeline sai → investigate sai hướng → kéo dài MTTR.

---

### 🧪 Experiment 11: Cache-Miss Storm (Redis Dependency)

> **📋 Runbook:** [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md#-rb-22-highlatencyp95) (latency tăng do DB overload khi cache miss)

> Dashboard `cache-performance` chưa bao giờ được dùng trong experiments trước — đây là experiment đầu tiên cover nó.

**Giả thuyết:** Khi Redis bị stop, tất cả requests phải query DB trực tiếp → DB load tăng đột ngột → P95 latency tăng. Cache-aside pattern là **single point of performance** dù không phải single point of failure.

**Inject (2 terminals):**

```bash
# Terminal 1: Stop Redis
docker stop redis
```

```bash
# Terminal 2: Chạy traffic (browse_heavy để maximize cache miss impact)
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "browse_heavy", "rate": 10, "duration": 120}'
```

**Dashboard reading path:**
```
Cache Performance → Hit Rate = 0% (hoặc no data), Latency = no data
  → DB Performance → query duration tăng, connection pool active tăng
    → App Performance → Order Service P95 tăng (mọi request hit DB)
      → Unified Overview → Error rate có thể tăng nếu DB overwhelmed
        → Tracing → span get_product_catalog chậm hơn bình thường
```

**Quan sát kỳ vọng:**
- Cache Performance dashboard: hit rate drop về 0, hoặc panels hiển thị "no data"
- DB Performance: query count tăng gấp nhiều lần (bình thường cache serve ~80% requests)
- App Performance: P95 tăng nhưng có thể **không tăng nhiều** nếu DB chưa quá tải — đây cũng là bài học
- So sánh: P95 khi có cache vs không cache → đo được **cache giá trị bao nhiêu ms**

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Cache dependency:** Redis down → service có crash không? Hay chỉ chậm hơn? Đây gọi là gì? (graceful degradation — service vẫn hoạt động, chỉ mất performance)
2. **Cache value measurement:** P95 khi có cache = ___ms, P95 khi không cache = ___ms. Cache giúp giảm bao nhiêu %?
3. **DB amplification:** Hit rate 80% nghĩa là DB chỉ serve 20% requests. Khi cache down, DB phải serve 100% — gấp **5 lần**. Connection pool có chịu được không?
4. **Cache-performance dashboard:** Panel nào cho thấy vấn đề nhanh nhất? Panel nào trở thành "no data" khi Redis down?
5. **Ứng dụng production:** Redis cluster bị restart lúc flash sale — bạn cần ước lượng gì trước khi cho traffic vào lại? (DB capacity có chịu được 100% traffic không? Cần warm cache trước không?)

**Bài học:** Cache-aside pattern che giấu DB performance issues. Khi cache down, DB load tăng **1 / (1 - hit_rate)** lần. Với hit rate 80%, DB load tăng 5x. Biết con số này giúp sizing DB cho worst case.

**Rollback:**
```bash
docker start redis
# Cache sẽ tự warm lại khi có requests mới (cache-aside pattern)
```

---

### 🧪 Experiment 12: Multi-Alert Triage (Compound Failure)

> **📋 Runbook:** [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md#-rb-22-highlatencyp95) · [RB-21 HighErrorRate](INCIDENT_RUNBOOK.md#-rb-21-higherrorrate) · [RB-16 KafkaConsumerLagHigh](INCIDENT_RUNBOOK.md#-rb-16-kafkaconsumerlaghigh-lag--100) · [RB-12 LatencyFastBurn](INCIDENT_RUNBOOK.md#-rb-12-apigatewaylatencyfastburn)

> Đây là experiment **khó nhất** — lần đầu tiên inject 2 failures cùng lúc. Mục tiêu không phải hiểu từng failure (đã làm ở Exp 2, 3) mà là luyện **kỹ năng triage khi nhiều alerts firing đồng thời**.

**Giả thuyết:** Khi DB bị lock VÀ notification-worker bị pause cùng lúc, 4-5 alerts sẽ firing đồng thời. On-call engineer phải phân biệt root cause vs symptom và quyết định fix cái nào trước.

**Inject (3 terminals):**

```bash
# Terminal 1: Flush cache + Lock DB table 90s
docker exec redis redis-cli DEL "product:catalog"
docker exec postgres psql -U app -d orders -c "
  BEGIN;
  LOCK TABLE products IN ACCESS EXCLUSIVE MODE;
  SELECT pg_sleep(90);
  COMMIT;
"
```

```bash
# Terminal 2: Pause notification-worker
docker pause notification-worker
```

```bash
# Terminal 3: Chạy traffic cao
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "browse_heavy", "rate": 20, "duration": 120}'
```

**Alerts kỳ vọng (có thể firing trong 5-10 phút):**

| Alert | Root cause? | Symptom? |
|-------|------------|----------|
| HighLatencyP95 | ← DB lock | Root cause #1 |
| HighErrorRate | ← timeout từ DB lock | Symptom of DB |
| KafkaConsumerLagHigh | ← notification-worker paused | Root cause #2 |
| APIGatewayLatencyFastBurn | ← cascade từ DB lock | Symptom of DB |

**Dashboard reading path:**
```
Alerting Overview → 4+ alerts firing cùng lúc
  → STOP. Đừng click vào alert đầu tiên. Đọc TẤT CẢ alerts trước.
    → Phân nhóm:
       Nhóm 1 (Latency/Error): HighLatencyP95 + HighErrorRate + LatencyFastBurn
         → Correlation: cùng liên quan latency → likely cùng root cause
       Nhóm 2 (Kafka): KafkaConsumerLagHigh
         → Không liên quan latency → root cause riêng
    → Fix Nhóm 1 trước (severity cao hơn, ảnh hưởng user trực tiếp)
    → Fix Nhóm 2 sau (lag tăng nhưng chưa ảnh hưởng user ngay)
```

**✅ Kỳ vọng & Câu hỏi kiểm tra:**

> Sau khi chạy experiment này, bạn phải trả lời được:

1. **Triage priority:** 4 alerts firing cùng lúc — bạn xử lý theo thứ tự nào? Tại sao? (Gợi ý: severity + user impact)
2. **Root cause vs symptom:** `HighErrorRate` là root cause hay symptom? Làm sao biết? (Nếu fix DB lock → error rate tự giảm → nó là symptom)
3. **Correlation:** Làm sao nhận ra `HighLatencyP95` + `HighErrorRate` + `LatencyFastBurn` cùng root cause? (timing gần nhau, cùng service, latency → error → burn rate là cascade)
4. **Independent failures:** `KafkaConsumerLagHigh` có liên quan tới DB lock không? Tại sao không? (notification-worker pause là inject riêng, DB lock không ảnh hưởng Kafka)
5. **Fix order:** Nếu bạn chỉ có thể fix 1 thứ trước — DB lock hay unpause worker? Tại sao? (DB lock → ảnh hưởng user trực tiếp; Kafka lag → delay notification nhưng user vẫn đặt hàng được)
6. **Ứng dụng production:** Lúc 3 giờ sáng nhận 5 alerts PagerDuty cùng lúc — bạn dùng kỹ thuật gì để không panic? (Đọc tất cả → phân nhóm → tìm correlation → fix root cause → symptoms tự resolve)

**Bài học:** Khi nhiều alerts firing, **đừng fix từng alert** — phân nhóm theo correlation, tìm root cause chung, fix root cause thì symptoms tự resolve. Đây là skill quan trọng nhất của on-call engineer.

**Rollback:**
```bash
# DB lock tự release sau 90s, hoặc:
docker exec postgres psql -U app -d orders -c "
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE state = 'active' AND query LIKE '%pg_sleep%';
"
# Unpause notification-worker
docker unpause notification-worker
```

---

## Part 3: Checklist sau mỗi Experiment

Sử dụng template sau cho mỗi bài thực hành:

```markdown
## Experiment: [Tên]
**Timestamp inject:** YYYY-MM-DD HH:MM:SS (UTC)

### Baseline (trước inject)
- [ ] Ghi baseline metrics (xem bảng "Cách đo Baseline")
- [ ] Chụp screenshot dashboards: Unified Overview, App Performance, dashboard liên quan

### Incident (trong inject)
- [ ] Alert nào đã firing? Sau bao lâu?
- [ ] **MTTD** = alert_firing_time − inject_time = ___ phút
- [ ] Dashboard nào cho thấy root cause nhanh nhất?
- [ ] Dashboard nào misleading hoặc không hữu ích?

### Recovery (sau rollback)
- [ ] Rollback thành công? Mất bao lâu?
- [ ] **MTTR** = recovery_time − inject_time = ___ phút
- [ ] Alert đã chuyển RESOLVED? Sau bao lâu kể từ rollback?
- [ ] Metrics đã trở về baseline? (so sánh với giá trị ghi ở bước Baseline)
- [ ] Chụp screenshot dashboards sau recovery

### Bài học
- [ ] Root cause:
- [ ] Bài học rút ra:
- [ ] Runbook cần update gì:
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
| 6 | SLO Burn Rate (Learning) | ⭐⭐⭐ | Error budgets, burn rate math, team playbooks |
| 7 | Cache-Miss Storm | ⭐⭐⭐ | Cache dependency, DB amplification, graceful degradation |
| 8 | DNS Cache | ⭐⭐⭐⭐ | Misleading dashboards, networking |
| 9 | Memory Pressure | ⭐⭐⭐⭐ | Infrastructure monitoring, predictive alerts |
| 10 | Phantom Alert | ⭐⭐⭐⭐ | Stale metrics, alert lifecycle, traffic guard |
| 11 | Timezone Trap | ⭐⭐ | Human error, UTC convention, cross-reference |
| 12 | Multi-Alert Triage | ⭐⭐⭐⭐⭐ | Compound failure, alert correlation, triage priority |

