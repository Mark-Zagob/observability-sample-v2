# Incident Log — Order Service down

**Start:** 2026-06-09 10:10:30 UTC+7  
**Alert(s):** `ServiceHealthCheckFailed`, `HighErrorRate` (api-gateway)  
**IC:** Dungtt (solo engineer)

---

## Baseline Snapshot (collected at 09:19:25 UTC+7)

Traffic: `scenario=normal`, `rate=2`, `duration=120s`  
System stable for 50 minutes before inject.

### Application

- API Gateway RPS: ~3.7 req/s
- Order Service RPS: ~0.35 req/s (from spanmetrics)
- Payment Error Rate: ~11.2% (intentional flakiness, baseline)
- API Gateway P95: 1.8s (aggregate, normal due to slow payment mix)
- Business — Order Success Rate: 88.7%

### Logs

- API Gateway: "Order created" mỗi ~500ms
- Order Service: "Processing new order" mỗi ~500ms

---

## Pre-Mortem Hypothesis (GHI TRƯỚC KHI INJECT)

- Alert Lớp 1 (Blackbox): sẽ fire sau ~60-75s (`for: 1m`)
- Alert Lớp 2 (SpanMetrics): sẽ fire sau ~300s (`absent_over_time[3m]` + `for: 2m`)
- API Gateway response: fail-fast 502 Bad Gateway
- API Gateway Latency: KHÔNG tăng (fail fast)
- API Gateway Error Rate: TĂNG VỌT ~100%
- Kafka produce rate: RỚT về 0 (order-service không publish)
- Consumer lag: KHÔNG TĂNG (không có event mới để lag)

---

## SEV Assessment
- **Initial SEV:** SEV-3
- **Impact Assessment:**
  1. Users affected: 100% users thực hiện checkout (nhưng tổng user online đang rất ít).
  2. Revenue impact: CÓ (mất đơn hàng), nhưng volume thấp do off-hours.
  3. Data loss: KHÔNG.
  4. Security: KHÔNG.
  5. SLA/SLO: Đang vi phạm Availability SLO (99.5%).
- **Context & Escalation:** 
  Đang là off-hours (rate=2). Theo Escalation Matrix, chưa cần page VP Eng/Finance ngay. 
  Sẽ tự xử lý (Solo Engineer). Nếu kéo dài > 15 phút (đến 10:25) mà không restore -> Escalate Team Lead.
- **Communication:** Không cần gửi Initial Notification cho #stakeholders do impact thấp. Chỉ log vào Slack channel #incidents-log.

---

## Timeline
- `[10:09:50]` 📊 Baseline established (rate=2). RPS GW: 3.7, Order: 0.35.
- `[10:10:30]` 💉 Inject: docker stop order-service

- `[10:11:20]` 🔍 Check Unified Overview
  - API GW RPS: 13.5 req/s (TĂNG BẤT THƯỜNG)
  - Order RPS: 0 req/s (DROP)
  - Payment Error: 12.2% (Bình thường)  
  🤔 Hypothesis #1: Traffic Surge / DDoS vào API Gateway  
  ❌ REJECT: Error Rate đang tăng, không phải traffic thật. RPS tăng do Gateway fail-fast 502 (Little's Law).

- `[10:12:19]` 🔔 Alert fired: ServiceHealthCheckFailed (RB-24)
- `[10:12:40]` 🤔 Hypothesis #2: Order Service process crashed hoặc network partition.
  - Action: Cần check App Performance để xem Gateway có nhận được 502 không.

- `[10:13:30]` 🔍 Check App Performance
  - GW Infra Error Rate: 27.1% (TĂNG)
  - Order Success Rate: 66.7% (GIẢM)  
  ✅ ACCEPT Hypothesis #2: Gateway đang trả về lỗi khi gọi Order. Vấn đề cô lập ở Order Service.

- `[10:13:47]` 🔔 Alert fired: HighErrorRate (api-gateway) -> Expected cascade.

- `[10:15:30]` 🔍 Check Kafka Overview (Kiểm tra Blast Radius downstream)
  - Produce Rate: 0 msg/s (Drop)
  - Consumer Lag: Giảm từ 2 -> 0  
  🧠 Architect Note: Lag KHÔNG tăng vì không có event mới được produce. Workers đang đói data (Starvation), không bị nghẽn (Congestion).

- `[10:17:30]` 🎯 Decision: Follow RB-24 Step 2 & 3 (Check container status)
  - Considered: Check OTel Collector logs -> REJECT (các service khác vẫn có metrics).
  - Considered: Check Docker logs -> REJECT (container có thể đã stop, không có logs mới).
  - Chọn: `docker ps -a` (nhanh nhất, definitive).

- `[10:18:00]` ⚡ Executed: `docker ps -a | grep order` -> Exited (0)
- `[10:18:10]` ⚡ Executed: `docker start order-service` (RB-24 Step 3 fix)

- `[10:19:00]` 🔁 Verify Recovery (RB-24 Step 4 - BẮT BUỘC)
  - `docker ps`: order-service Up (healthy)
  - Alerting Overview: ServiceHealthCheckFailed -> RESOLVED
  - Unified Overview: API GW RPS về 3.8, Order RPS về 0.35
  - Kafka: Produce rate back to ~2 msg/s
- `[10:19:30]` ✅ Incident Resolved. MTTR = 9 phút.

---

## Recovery & Verification

- `[10:18:40]` 👀 Verify: `docker ps` → `order-service (healthy)`
- `[10:19:00]` 🔁 Alerting Overview:
  - `ServiceHealthCheckFailed` → RESOLVED
  - `HighErrorRate` → RESOLVED
  - `ServiceNoTraces_OrderService` → KHÔNG fire (do rollback sớm)
- `[10:19:30]` 🧪 Recovery traffic test:

```bash
  curl -X POST http://localhost:5003/start \
    -H "Content-Type: application/json" \
    -d '{"scenario": "normal", "rate": 2, "duration": 30}'
```

- `[10:20:30]` ✅ Verified recovery:
  - Order Service RPS: ~2 req/s (baseline restored)
  - Error rate: ~10% (baseline restored)
  - Kafka produce rate: ~2 msg/s (restored)
  - Consumer lag: stable
- `[10:20:30]` ✅ **Incident resolved**

---

## Incident Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **MTTD** (Detect) | 1m 49s (Inject → Alert) | < 5 min | ✅ |
| **MTTA** (Acknowledge) | ~0s (solo engineer) | < 5 min | ✅ |
| **MTTR** (Resolve) | 7m 40s (Inject → Start recovery) | < 1h | ✅ |
| **Observation gap** | 50s (inject → first dashboard check) | — | ⚠️ |

> **Improvement:** auto-open dashboard khi alert fire để giảm observation gap.

---

## Decisions Log

| Time | Decision | Reason | Alternative considered |
|------|----------|--------|------------------------|
| 10:12:40 | Investigate Order Service | RPS = 0 | Check API Gateway first |
| 10:17:45 | Check `docker ps` | Fastest verification | Check logs / OTel |
| 10:18:10 | Restart container | Stateless service | Investigate root cause first |

---

## Key Learnings

1. **2-layer monitoring confirm:** Alert Lớp 1 fire nhanh (1m49s), Alert Lớp 2 cần traffic + thời gian dài hơn (5 phút).
2. **Kafka correlation:** Producer chết → consumer lag KHÔNG tăng (counter-intuitive, cần ghi nhớ).
3. **Prediction accuracy:** 5/5 predictions đúng → hypothesis method works.
4. **Missed learning:** Không thấy alert Lớp 2 do rollback sớm. Lần sau nên đợi đủ 5 phút HOẶC ghi rõ "not verified".