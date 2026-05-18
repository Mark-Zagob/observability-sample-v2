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
| Connection pool active | 10/10 | 3-4/10 🔴 Pool đầy |
| Avg query duration | 2.5s | 5ms 🔴 Gấp 500 lần |
| Slow queries | 38 | 0 🔴 |

→ **Root cause:** DB bị saturated. Kiểm tra Loki logs → PostgreSQL autovacuum đang chạy trên bảng `orders`, lock table → mọi INSERT phải chờ.

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
| 6 | SLO Burn Rate (Learning) | ⭐⭐⭐ | Error budgets, burn rate math, team playbooks |
| 7 | DNS Cache | ⭐⭐⭐⭐ | Misleading dashboards, networking |
| 8 | Memory Pressure | ⭐⭐⭐⭐ | Infrastructure monitoring, predictive alerts |
