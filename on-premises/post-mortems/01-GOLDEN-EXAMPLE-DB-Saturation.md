# 🏆 Golden Example: DB Saturation (Experiment 2)

> **Mục đích:** Đây là "tiêu chuẩn vàng" để tham khảo khi viết post-mortem cho các experiments khác.
> **Experiment:** [Exp 2: Database Saturation](../INCIDENT_SIMULATION_GUIDE.md#-experiment-2-database-saturation-high-latency)
> **Tình huống giả định:** Flash sale scenario, traffic `browse_heavy` rate 20 req/s, DB table lock 90s

---

## 📋 Incident Log (Real-time)

**Start:** 2026-05-22 14:32 UTC  
**Alert(s):** HighLatencyP95 (Order Service), HighErrorRate, APIGatewayLatencyFastBurn  
**IC:** Me (solo engineer)

### SEV Assessment (ghi trong 30s đầu)
- **Initial SEV:** SEV-2
  - Lý do:
    - Nhiều users bị ảnh hưởng (browse_heavy traffic = 20 req/s)
    - Feature chính (checkout/browsing) bị ảnh hưởng
    - Không có data loss
    - Không có security issue
    - Không có SLA contractual với customer
- **Escalation decision:** Không escalate ngay, sẽ escalate Team Lead nếu > 15 phút không resolve (theo Escalation Matrix)

### Timeline
- [14:32] 🔔 Alert fired: HighLatencyP95 (Order Service) - critical
- [14:32] 👀 Ack alert, mở Incident Log, ghi Initial SEV-2
- [14:33] 🔍 Check Alerting Overview → 3 alerts firing: HighLatencyP95, HighErrorRate, LatencyFastBurn
  - Observation: Tất cả liên quan latency → likely cùng root cause
- [14:34] 🔍 Check Unified Overview
  - RPS: 45 req/s (bình thường)
  - Error Rate: 12% (cao, bình thường < 1%)
  - P95 Latency: 3.2s (bình thường 400ms) → tăng 8x
- [14:35] 🤔 Hypothesis #1: Traffic surge gây overload
  - Check: RPS vẫn 45 req/s → **REJECT** (không phải traffic issue)
- [14:36] 🔍 Check App Performance → Order Service section
  - P95: 3.1s (tăng từ 400ms baseline)
  - Payment Service P95: 200ms (bình thường)
  - Observation: Chỉ order-service chậm, payment OK → bottleneck trong order-service
- [14:37] 🤔 Hypothesis #2: Order service code bug hoặc resource issue
- [14:38] 🔍 Check Tracing → sort by duration descending
  - Longest trace: 3.2s total
  - Span breakdown:
    - `get_product_catalog`: 2.8s (87% tổng thời gian) ← BOTTLENECK
    - `validate_input`: 15ms
    - `insert_order`: 180ms
    - `request_payment`: 200ms
- [14:39] 🤔 Hypothesis refined: `get_product_catalog` span chậm → likely DB hoặc cache issue
- [14:40] 🔍 Check DB Performance dashboard
  - Connection pool: 10/10 (đầy, bình thường 2-3/10)
  - Avg query duration: 2.5s (bình thường 5ms) → tăng 500x
  - Active queries: 38 queries đang chạy, tất cả SELECT trên `products` table
- [14:41] 🤔 Hypothesis confirmed: DB saturated, connection pool exhausted
- [14:42] 🔍 Check Cache Performance
  - Hit rate: 0% (bình thường 85%)
  - Observation: Cache miss → tất cả requests phải query DB → pool đầy
- [14:43] 🎯 Decision: Kill long-running queries trong PostgreSQL
  - **Reason:** Stop the bleeding ngay, investigate root cause sau
  - **Considered alternatives:**
    - Restart order-service: Không fix root cause (DB vẫn locked)
    - Increase connection pool: Cần restart service, mất thời gian
    - Wait for lock release: Không biết khi nào release, users đang chịu impact
  - **Risk:** Có thể kill legitimate queries, nhưng accept được vì đang incident
- [14:44] ⚡ Executed:
  ```bash
  docker exec postgres psql -U app -d orders -c "
    SELECT pg_terminate_backend(pid) FROM pg_stat_activity
    WHERE state = 'active' AND query LIKE '%pg_sleep%';
  "