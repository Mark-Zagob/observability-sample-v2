# Blameless Post-Mortem: DB Saturation (Connection Pool Bottleneck)

**Date:** 2026-06-12  
**Duration:** 10 phút (08:24:30Z - 08:34:30Z)  
**SEV:** 4 (Initial: SEV-3, Re-assessed: SEV-4)  
**Incident Commander:** dungtt (solo engineer)  
**Participants:** dungtt

---

## 📋 Executive Summary

Vào lúc 15:24 UTC+7 (08:24 UTC), hệ thống E-commerce gặp sự cố **Database Connection Pool Exhaustion** khi chạy load test với traffic 20 req/s. Nguyên nhân gốc rễ là **capacity planning gap**: Gunicorn spawn 16 concurrent threads nhưng DB connection pool chỉ có 10 connections, dẫn đến 6 threads phải xếp hàng chờ (queue) khi có DB lock. Sự cố khiến P95 latency tăng từ 400ms lên 30s, gây timeout cho tất cả requests. Hệ thống tự phục hồi sau 90s khi DB lock được giải phóng.

**Impact:** 0 users thật bị ảnh hưởng (đây là load test trong lab). Không có revenue loss. Error Budget không bị tiêu thụ.

---

## 🎯 Impact

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Users affected | 0 (synthetic traffic only) | — | ✅ |
| Revenue impact | $0 | — | ✅ |
| Error Budget consumed | 0% | < 5% per incident | ✅ |
| Customer complaints | 0 | — | ✅ |
| MTTD (Detect) | 2 phút 20 giây | < 5 phút | ✅ |
| MTTA (Acknowledge) | 2 phút 30 giây | < 5 phút | ✅ |
| MTTR (Resolve) | 10 phút | < 60 phút (SEV-2) | ✅ |

---

## 📅 Timeline (UTC)

| Time (UTC) | Event |
|------------|-------|
| 08:24:30 | 💉 **Inject:** Chạy `inject_db_saturation.sh` (traffic 20 req/s + cache flush + DB lock 90s) |
| 08:24:40 | 🔍 **Check Unified Overview:** Order Service RPS giảm từ 4.33 → 0.06 req/s |
| 08:25:00 | 🔍 **Check DB Performance:** Pool Utilization 80%, Wait Time P95 = 25ms |
| 08:25:30 | 🤔 **Hypothesis #1:** "Kết nối không ổn định giữa các services" → **REJECT** (không có network errors) |
| 08:26:00 | 🤔 **Hypothesis #2:** "Database Postgres có vấn đề" → **REFINE** (cần drill-down sâu hơn) |
| 08:27:50 | 🔔 **Alert fired:** `HighLatencyP95` (api-gateway) |
| 08:28:50 | 🔔 **Alert fired:** `HighLatencyP95` (order-service) |
| 08:29:00 | 🔍 **Check DB Performance:** Connection Pool Activity = 10/10 (100%) |
| 08:30:00 | 🤔 **Hypothesis confirmed:** "Connection Pool exhausted do Gunicorn 16 threads vs `DB_POOL_MAX=10`" |
| 08:33:50 | ✅ **Alert resolved:** DB lock tự giải phóng sau 90s |
| 08:34:30 | 🔁 **Monitoring confirmed recovery:** RPS hồi phục, Pool về baseline |

---

## 🔍 Root Cause Analysis (5 Whys)

**Why 1:** Tại sao P95 latency tăng từ 400ms lên 30s?  
→ Requests bị timeout khi chờ connection từ pool (wait time = 30s)

**Why 2:** Tại sao requests phải chờ connection?  
→ DB connection pool đã đầy (10/10 connections đều bị treo do `LOCK TABLE`)

**Why 3:** Tại sao pool đầy khi chỉ có 10 connections?  
→ Gunicorn spawn 16 concurrent threads, nhưng pool chỉ có 10 connections → 6 threads phải queue

**Why 4:** Tại sao mismatch này tồn tại (16 threads vs 10 pool)?  
→ Không ai tính pool sizing khi setup service. `DB_POOL_MAX = 10` được set arbitrary (conservative) mà không dựa trên concurrency model

**Why 5:** Tại sao không có process tính pool sizing?  
→ **Systemic gap:** Thiếu capacity planning checklist và pre-deployment validation cho connection pool sizing

**Root Cause:** **Design-level Failure** — Không có process capacity planning để match Gunicorn concurrency với DB connection pool size.

---

## ✅ What Went Well

1. **Baseline Snapshot chi tiết:** Ghi lại đầy đủ metrics trước khi inject giúp so sánh before/after dễ dàng
2. **Pre-Mortem Hypothesis:** Ghi hypothesis TRƯỚC KHI inject giúp tránh confirmation bias
3. **SEV Assessment đúng:** Phân SEV-3 (off-hours) thay vì SEV-1 (flash sale) → không over-escalate
4. **Decision Log:** Ghi lại decisions real-time giúp post-mortem chính xác

---

## ❌ What Went Poorly

1. **Hypothesis quá vague:** "DB có vấn đề" không đủ sâu, bỏ qua capacity planning gap
2. **Timeline timezone mismatch:** Ghi 15:24 UTC+7 và 10:27 UTC → khó cross-reference
3. **Không đọc Golden Example:** Viết post-mortem mà không biết tiêu chuẩn vàng trông như thế nào
4. **Thiếu Action Items trackable:** Không có owner, deadline, priority cho các fixes

---

## 🎯 SEV Assessment Deep Dive

### Initial SEV: SEV-3

**Lý do:**

- Users affected: 100% users thực hiện checkout (nhưng tổng user online đang rất ít)
- Revenue impact: CÓ (mất đơn hàng), nhưng volume thấp do off-hours
- Data loss: KHÔNG
- Security: KHÔNG
- SLA/SLO: Đang vi phạm Latency Compliance (99.5%)

### Re-assessed SEV: SEV-4

**Lý do sau khi investigate:**

- Đây là **synthetic traffic** (load test), không phải user thật
- Blast radius = 0 đối với production users
- Hệ thống tự phục hồi sau 90s (DB lock release)

### So sánh với Context Matrix

| Context | SEV | Escalation |
|---------|-----|------------|
| **Context A:** Off-hours, `rate=2` (thực tế) | SEV-4 | Tạo ticket, xử lý trong business hours |
| **Context B:** Flash sale, `rate=20` (giả định) | SEV-1 | Page VP Eng + Finance ngay lập tức |

> **Bài học:** SEV phụ thuộc vào **business context**, không chỉ technical signal. Alert "critical" lúc 3 AM không traffic ≠ alert "critical" lúc flash sale.

---

## 🛠️ Action Items (SMART)

| # | Action | Owner | Deadline | Priority | Status |
|---|--------|-------|----------|----------|--------|
| 1 | **[Fix]** Tăng `DB_POOL_MAX` từ 10 lên 20 trong `app.py` và `docker-compose.yml` | @dungtt | 2026-06-15 | P1 | Open |
| 2 | **[Prevent]** Deploy PgBouncer (transaction mode) giữa App và PostgreSQL. Config: App pool = 20, PgBouncer pool = 100, PostgreSQL `max_connections` = 120 | @dungtt | 2026-06-30 | P1 | Open |
| 3 | **[Detect]** Thêm alert `DBPoolWaitTimeHigh` trong `alert_rules.yml`: P95 > 1s trong 2 phút → `severity: warning` | @dungtt | 2026-06-20 | P2 | Open |
| 4 | **[Process]** Tạo `docs/capacity-planning-checklist.md` với pool sizing formula và pre-deployment validation | @dungtt | 2026-06-25 | P2 | Open |
| 5 | **[Process]** Thêm vào `INCIDENT_RUNBOOK.md` rule: "LUÔN dùng UTC cho incident logs. Grafana set timezone = UTC" | @dungtt | 2026-06-20 | P2 | Open |

### Chi tiết Action Item #3: Alert `DBPoolWaitTimeHigh`

Thêm vào `alert_rules.yml`:

```yaml
- alert: DBPoolWaitTimeHigh
  expr: |
    histogram_quantile(0.95,
      sum(rate(db_pool_wait_duration_seconds_bucket{
        job="app-metrics",
        service_name="order-service"
      }[5m])) by (le)
    ) > 1
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "🟡 DB Pool Wait Time P95 > 1s"
    description: "Connection pool đang queue. P95 wait time = {{ $value }}s. Có thể dẫn đến timeout nếu kéo dài."
```

**Tại sao alert này quan trọng?**

- Đây là **Leading Indicator** (báo TRƯỚC khi user bị ảnh hưởng)
- `HighLatencyP95` là **Lagging Indicator** (user đã bị ảnh hưởng rồi)
- Production teams LUÔN monitor leading indicators để proactive fix

### Chi tiết Action Item #4: Capacity Planning Checklist

Tạo file `docs/capacity-planning-checklist.md`:

```markdown
# Capacity Planning Checklist

## Connection Pool Sizing

### Formula (PostgreSQL standard):
max_connections = (core_count × 2) + effective_spindle_count

### Pre-Deployment Validation:
1. **Check Gunicorn config**: `--workers X --threads Y` → Total concurrent = X × Y
2. **Check `DB_POOL_MAX`** trong code
3. **Verify**: `DB_POOL_MAX` ≥ Gunicorn concurrent requests
4. **If mismatch**:
   - Option 1: Tăng `DB_POOL_MAX`
   - Option 2: Giảm Gunicorn threads
   - Option 3 (Production): Deploy PgBouncer

### PgBouncer Configuration (Production):
App → PgBouncer (transaction mode) → PostgreSQL
  App pool:                   20 connections per service
  PgBouncer pool:            100 connections total
  PostgreSQL max_connections: 120 (100 + 20 reserved for admin)

### Monitoring:
- Leading Indicator:  `DB Pool Wait Time (P95)` < 100ms
- Lagging Indicator:  `HighLatencyP95` alert
- Saturation:         `DB Connection Pool Activity` = 10/10
```

---

## 📚 Lessons Learned

1. **Leading vs Lagging Indicators:** DB Pool Wait Time là leading indicator (báo TRƯỚC khi user bị ảnh hưởng), `HighLatencyP95` là lagging indicator (user đã bị ảnh hưởng rồi). Production teams LUÔN monitor leading indicators để proactive fix.

2. **Capacity Planning Gap:** Mismatch giữa Gunicorn concurrency (16 threads) và DB connection pool (10 connections) là design-level failure, không phải infrastructure failure hay code bug. Cần capacity planning checklist để prevent.

3. **SEV phụ thuộc vào Business Context:** Alert "critical" lúc 3 AM không traffic (SEV-4) ≠ alert "critical" lúc flash sale (SEV-1). On-call engineer giỏi biết khi nào cần gọi sếp dậy, khi nào chỉ cần tạo ticket.

---

## 📊 Metrics Summary

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| MTTD (Detect) | 2 phút 20 giây | < 5 phút | ✅ |
| MTTA (Acknowledge) | 2 phút 30 giây | < 5 phút | ✅ |
| MTTR (Resolve) | 10 phút | < 60 phút (SEV-2) | ✅ |
| Error Budget consumed | 0% | < 5% per incident | ✅ |
| SEV assessment accuracy | Match (SEV-3 → SEV-4) | Match | ✅ |

---

## 🔁 Follow-up Schedule

- [ ] **48h:** Review post-mortem, đảm bảo action items rõ ràng
- [ ] **1 week:** Check-in progress P1 action items (tăng pool size, deploy PgBouncer)
- [ ] **1 month:** Verify all action items completed
- [ ] **Quarterly:** Reliability review — xu hướng incidents tương tự

---

## 🛡️ Blameless Principles

| ❌ Blame | ✅ System Gap |
|---------|-------------|
| "Tôi đã quên tính pool sizing khi setup" | "Thiếu capacity planning checklist và pre-deployment validation" |
| "Tôi không đọc code đủ sâu" | "Cần training về Python concurrency model và DB connection pooling" |

> **Rule:** Mọi "human error" đều là system gap. Hệ thống tốt khiến human error khó xảy ra hoặc ít impact.