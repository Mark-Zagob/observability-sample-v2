# Incident Log — DB Saturation (Connection Pool Bottleneck)

**Start:** 2026-06-12 15:24:30 UTC+7  
**Alert(s):** `HighLatencyP95`  
**IC:** Dungtt (solo engineer)

---

## Baseline Snapshot (collected at 14:54:00 UTC+7)

Traffic: `scenario=normal`, `rate=2`, `duration=120s`  
System stable for 30 minutes before inject.

### Application Layer (Dashboard: Unified Overview)
- API Gateway RPS: 0.168 req/s
- Order Service RPS: 4.33 req/s
- Payment Service RPS: 11.4 req/s
- Error Rate: 13.6%
- P95 Latency (API Gateway): 900 ms

### Database Layer (Dashboard: DB Performance)
- Connection Pool Active: 0 / 10
- Connection Pool Wait Time (P95): 4.75 ms
- Avg Query Duration: 31.9 ms (INSERT) - 1.19 ms (SELECT) - 30.2 ms (UPDATE)
- Pool Saturation Status: 🟢 Healthy

### Cache Layer (Dashboard: Cache Performance)
- Cache Hit Ratio: 56.8%
- Cache GET Latency (P95): 4.75ms

### Kafka Layer (Dashboard: Kafka Overview)
- notification-workers lag: 5 groups
- inventory-workers lag: 8 groups

### Infrastructure (Dashboard: Node Exporter - vm=app)
- CPU Usage: 14.7%
- Memory Usage: 6.49%
- Disk Usage: 14.3%

### Alerts (Dashboard: Alerting Overview)
- Firing Alerts: 1 (chỉ Watchdog)
- Critical: 0
- Warning: 1 - HighErrorRate - Payment Service

### Logs

- API Gateway: "Order created" mỗi ~500ms
- Order Service: "Processing new order" mỗi ~500ms

---

## Pre-Mortem Hypothesis (GHI TRƯỚC KHI INJECT)


---

## SEV Assessment
- **Initial SEV:** SEV-3
- **Impact Assessment:**
  1. Users affected: 100% users thực hiện checkout (nhưng tổng user online đang rất ít).
  2. Revenue impact: CÓ (mất đơn hàng), nhưng volume thấp do off-hours.
  3. Data loss: KHÔNG.
  4. Security: KHÔNG.
  5. SLA/SLO: Đang vi phạm Latency Compliance (99.5%).
- **Context & Escalation:** 
  Đang là off-hours (rate=2). Theo Escalation Matrix, chưa cần page VP Eng/Finance ngay. 
  Sẽ tự xử lý (Solo Engineer). Nếu kéo dài > 15 phút (đến 10:25) mà không restore -> Escalate Team Lead.
- **Communication:** Không cần gửi Initial Notification cho #stakeholders do impact thấp. Chỉ log vào Slack channel #incidents-log.

---

## Timeline

- `[15:24:00]` 💉 Inject: inject_db_saturation.sh script
- `[15:24:10]` 🔍 Check Unified Overview
  - API GW RPS: 0.14 req/s 
  - Order RPS: 0.06 req/s (Giảm bất thường)
  - Payment RPS: 0.025 req/s (Giảm bất thường)
  - Payment Error: 14.3% (Bình thường)  
  - Latency Burn Rate: Fast(5m) has value 11.4 at peak
- `[15:24:30]` 🔍 Check App Performance
  - GW Infra Error Rate: 22.5% (TĂNG)
  - API Gateway Duration P95: 9.6s (Tăng)
- `[15:24:40]` 🔍 Check Alert Overview
  - 3 ServiceNoTraces Alerts (Api gw, orders, payment) at pending status
  🤔 Hypothesis #1: kết nối không ổn định giữa các services
- `[15:25:00]` 🔍 Check DB Performance
  - DB Connection Pool Utilization: 80% tăng bất thường
  - DB Connection Pool Activity : 10 đạt max fullsize
  - DB Pool Wait Time (P95): 25ms (tăng cao bất thường)
  🤔 Hypothesis #2: Database Postgres có vấn đề
- `[10:27:50]` 🔔 Alert fired: HighLatencyP95 (api-gateway)
- `[10:28:50]` 🔔 Alert fired: HighLatencyP95 (order service)
- `[10:33:50]` 🔔 Alert resolved

---