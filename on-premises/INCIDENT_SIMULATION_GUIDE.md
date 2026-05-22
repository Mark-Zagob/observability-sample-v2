# 🚨 Incident Simulation Guide (Production-Grade)

## Mục tiêu
Hướng dẫn đọc dashboard theo chuẩn production-grade bằng phương pháp **Incident Flow** – đi theo luồng sự cố thực tế thay vì đọc từng dashboard rời rạc. Kèm 12 bài thực hành giả lập incident và **Framework quản lý incident (Part 0)** để rèn luyện tư duy ra quyết định, giao tiếp và hậu kỳ như một SRE/DevOps Engineer thực thụ.

**Prerequisite:** Hệ thống observability-lab đang chạy (applications-vm + observability-vm). Đã đọc qua `INCIDENT_RUNBOOK.md`.

---

## Mục lục
- [Part 0: Incident Management Fundamentals](#part-0-incident-management-fundamentals)
- [Part 1: Phương pháp đọc Dashboard](#part-1-phương-pháp-đọc-dashboard)
- [Part 2: Bài thực hành - Giả lập Incident](#part-2-bài-thực-hành--giả-lập-incident)
- [Part 3: Post-Exercise Activities (Hậu kỳ & Post-Mortem)](#part-3-post-exercise-activities-hậu-kỳ--post-mortem)
- [Part 4: Thứ tự thực hành đề xuất](#part-4-thứ-tự-thực-hành-đề-xuất)

---

# Part 0: Incident Management Fundamentals

> **Mục tiêu:** Trước khi học đọc dashboard, cần hiểu **cách một production team vận hành quanh incident**. Phần này bổ sung context về People & Process mà `INCIDENT_RUNBOOK.md` không cover (RUNBOOK là reference tra cứu nhanh, còn đây là learning framework).

## 0.1 Hai lớp Severity — Burn-Rate vs Impact-Based

RUNBOOK phân loại severity dựa trên **technical signal** (SLO burn rate): `critical` (fast burn 14.4x) / `warning` (slow burn 3x).
Production teams dùng thêm một lớp **impact-based SEV classification** để quyết định quy mô response. Hai lớp này **bổ sung nhau**.

### Impact-Based SEV Matrix (chuẩn PagerDuty/Atlassian)
| SEV | Impact | Response | Escalation | Ví dụ trong lab |
|-----|--------|----------|------------|-----------------|
| SEV-1 | Toàn bộ users mất service, revenue impact | 24/7, < 5 min page | VP Eng + Finance | Payment + Order cùng down |
| SEV-2 | Feature chính bị ảnh hưởng nhiều users | 24/7, < 15 min page | Team Lead | API Gateway FastBurn |
| SEV-3 | Performance degradation, 1 feature | Business hours, < 1h | On-call engineer | Kafka lag đơn lẻ |
| SEV-4 | Minor, không ảnh hưởng users | Next business day | Tạo ticket | Disk > 80% |

### Impact Assessment Questions (5 câu trước khi phân SEV)
1. **Bao nhiêu % users bị ảnh hưởng?** (100% → SEV-1)
2. **Có ảnh hưởng revenue trực tiếp không?** (Payment down → upgrade SEV)
3. **Có data loss hoặc corruption không?** (Có → SEV-1)
4. **Có security implication không?** (Data breach → SEV-1 + Security team)
5. **Có SLA/SLO contractual commitment bị vi phạm không?**

## 0.2 Incident Roles — Ai làm gì?
| Role | Trách nhiệm | Solo adaptation |
|------|-------------|-----------------|
| **Incident Commander (IC)** | Điều phối, ra quyết định, quản lý timeline | = Bạn |
| **Subject Matter Expert (SME)** | Debug sâu, fix code/config | = Bạn |
| **Scribe** | Ghi timeline, decisions **real-time** | = Bạn (bắt buộc!) |
| **Communication Lead** | Update stakeholders | = Bạn (nếu có impact) |

**Quy tắc cho Solo Engineer:** Mọi action phải log timestamp + decision reason. Dùng Incident Log Format (0.3).

## 0.3 Incident Log Format — Ghi real-time
Copy template này vào file text/Notion khi alert bắt đầu firing:

```markdown
# Incident Log — [Tên incident ngắn]
**Start:** YYYY-MM-DD HH:MM UTC | **SEV:** [1/2/3/4] | **IC:** [Tên bạn]

## Timeline
- [HH:MM] 🔔 Alert fired: [tên alert]
- [HH:MM] 👀 Ack alert, bắt đầu investigate
- [HH:MM] 🔍 Check [dashboard X] → thấy [observation]
- [HH:MM] 🤔 Hypothesis: [giả thuyết root cause]
- [HH:MM] 🎯 Decision: [action] vì [reason]
  - Considered: [alternative đã cân nhắc]
- [HH:MM] ⚡ Executed: [kết quả]
- [HH:MM] ✅ Alert resolved

## Decisions Log
| Time | Decision | Reason | Alternative considered |
|------|----------|--------|----------------------|
```

## 0.4 Decision Framework — Ra quyết định dưới áp lực
### Rollback vs Fix Forward
| Tình huống | Decision | Lý do |
|------------|----------|-------|
| Deploy mới trong 30 phút | **Rollback** | An toàn nhất, investigate sau |
| Code đã chạy > 24h | **Fix forward** | Rollback có thể gây data inconsistency |
| Unknown root cause | **Rollback nếu có thể** | Stop the bleeding |
| Database schema change | **KHÔNG rollback** | Data migration không reversible |

### Stop-the-Bleeding Priority (khi panic)
1. **Stop customer impact** > Find root cause
2. **Mitigation (workaround)** > Perfect fix
3. **Communication** > Silence
4. **Preserve evidence** > Clean up (nhưng preserve evidence *sau khi* stop impact)

## 0.5 Enhanced Post-Mortem & 5 Whys
Sau incident, dùng **5 Whys** để tìm systemic gap:
1. **Why** P95 latency cao? → DB queries bị block
2. **Why** queries bị block? → Connection pool exhausted
3. **Why** pool exhausted? → 16 concurrent threads vs pool max 10
4. **Why** mismatch này tồn tại? → Không ai tính pool sizing khi setup
5. **Why** không có process tính pool sizing? → Thiếu capacity planning checklist
→ **Action item thực sự:** Tạo capacity planning checklist, không chỉ "tăng pool size".

## 0.6 Incident Metrics to Track
| Metric | Formula | Target |
|--------|---------|--------|
| **MTTD** (Detect) | Alert fired − Incident start | < 5 min |
| **MTTA** (Acknowledge) | Ack − Alert fired | < 5 min |
| **MTTR** (Resolve) | Resolved − Incident start | < 1h cho SEV-2 |

## 0.7 Cách tích hợp với RUNBOOK
1. Alert firing → Mở **RUNBOOK** tìm alert → follow triage steps.
2. Song song: Mở **Incident Log (0.3)** → ghi real-time.
3. Khi cần quyết định khó → tham khảo **Decision Framework (0.4)**.
4. Communication → dùng templates trong RUNBOOK Part 5.
5. Sau incident → dùng **Part 3** của guide này để viết Post-Mortem.

---

# Part 1: Phương pháp đọc Dashboard

## 1.1 Hai phương pháp chuẩn ngành
| Phương pháp | Áp dụng cho | Câu hỏi trả lời |
|-------------|-------------|-----------------|
| **RED** (Rate, Errors, Duration) | Application / Service | Service có hoạt động tốt không? |
| **USE** (Utilization, Saturation, Errors) | Infrastructure / Resource | Resource có đủ không? |

**Quan trọng:** RED cho services, USE cho resources. Đừng dùng ngược – hỏi "utilization" của API Gateway vô nghĩa, hỏi "request rate" của CPU cũng vậy.

## 1.2 Dashboard Inventory
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
| Logging | docker-logs | Container logs (Loki) |
| Tracing | tracing-overview | Trace count, error traces, span durations |

## 1.3 Incident Flow – Đọc dashboard theo luồng sự cố
```text
                    +---------------------+
                    |  🚨 Alert Firing    |  → Điểm bắt đầu
                    +---------------------+
                               ↓
                    +---------------------+
              ⬇    |  Alerting Overview   |  Alert nào? Severity? Bao lâu rồi?
                    +---------------------+
                               ↓
                    +---------------------+
              ⬇    |  Unified Overview    |  Service nào ảnh hưởng? Phạm vi?
                    +---------------------+
                               ↓
              +----------------+----------------+
              ↓                ↓                ↓
    +---------+-----+  +------+------+  +------+------+
 ⬇  |App Performance|  |SLO Overview |  |Infrastructure|
    |  RED metrics  |  |Error Budget |  |  USE metrics |
    +---------------+  +-------------+  +--------------+
              ↓
    +---------+---------+
 ⬇  |  Tracing Overview  |  Request chain? Span nào chậm?
    +-------------------+
              ↓
    +---------+-----------------------------+
 ⬇  |  DB / Cache / Kafka Performance      |  Bottleneck ở đâu?
    +---------------------------------------+
```

## 1.4 Ví dụ thực tế: Đọc Incident Flow end-to-end
**Tình huống:** Nhận alert `APIGatewayLatencyFastBurn` (critical). Khách phàn nàn đặt hàng mất 3-5 giây.

1. **Alerting Overview:** Chỉ có Latency alert, không có Availability → service không down, chỉ chậm.
2. **Unified Overview:** RPS bình thường (45 req/s), Error Rate thấp (0.3%), P95 Latency = 3.2s (bình thường 500ms) → Không phải traffic surge, không phải lỗi logic.
3. **App Performance:** Payment P95 = 200ms (OK), Order Service P95 = 3.1s (CHẬM) → Bottleneck nằm trong order-service.
4. **Tracing:** Mở trace 3.2s → `insert_order` (DB write) chiếm 2.8s (87% tổng thời gian).
5. **DB Performance:** Connection pool 10/10 (đầy), Avg query duration 2.5s (gấp 500 lần) → DB saturated.
6. **Logs (Loki):** PostgreSQL autovacuum đang chạy trên bảng `orders`, lock table.

**Bài học:** Không dashboard nào đơn lẻ cho đủ thông tin. Mỗi bước thu hẹp phạm vi cho đến khi tìm ra root cause.

---

# Part 2: Bài thực hành - Giả lập Incident

> ⚠️ **Cảnh báo:** Tất cả thực hành trên lab environment. Không bao giờ chạy chaos experiments trên production mà không có safety controls.
> 💡 **Lưu ý khi thực hành:** Trong quá trình chạy mỗi Experiment, hãy mở một file text và thực hành ghi **Incident Log (real-time)** theo template ở [Mục 0.3](#03-incident-log-format--ghi-real-time). Đừng chỉ tập trung fix, hãy tập ghi lại *decision-making process* của bạn.

### Cách đo Baseline (bắt buộc trước mỗi Experiment)
Chạy traffic nhẹ để tạo baseline data:
```bash
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 60}'
```
Ghi lại các chỉ số: RPS (~2 req/s), Error rate (<1%), P95 (300-600ms), DB Pool (1-3/10), Cache Hit (>80%), Kafka Lag (0-5).

---

## 🧪 Experiment 1: Service Down (Health Check Failed)
**Runbook:** [RB-24 ServiceHealthCheckFailed](INCIDENT_RUNBOOK.md)
**Inject:** `docker stop order-service`
**Dashboard path:** Alerting Overview → Unified Overview → Kafka Overview
**Kỳ vọng & Câu hỏi kiểm tra:**
- `ServiceHealthCheckFailed` firing sau ~1 phút (Blackbox Exporter probe).
- **Down vs Slow:** Service down hiển thị thế nào trên dashboard? (no data, RPS = 0).
- **2 lớp monitoring:** Tại sao `TargetDown` không firing mà `ServiceHealthCheckFailed` lại firing?
**Rollback:** `docker start order-service`

## 🧪 Experiment 2: Database Saturation (High Latency)
**Runbook:** [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md)
**Inject (3 terminals song song):**
```bash
# T1: Flush cache
docker exec redis redis-cli DEL "product:catalog"
# T2: Lock DB 90s
docker exec postgres psql -U app -d orders -c "BEGIN; LOCK TABLE products IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(90); COMMIT;"
# T3: Traffic cao
curl -X POST http://localhost:5003/start -H "Content-Type: application/json" -d '{"scenario": "browse_heavy", "rate": 20, "duration": 120}'
```
**Kỳ vọng & Câu hỏi kiểm tra:**
- P95 latency tăng vọt, DB pool 10/10.
- **USE method:** DB saturation thể hiện ở metric nào?
- **Trace reading:** Mở 1 slow trace → span nào chiếm % lớn nhất?
- **Cache interaction:** Nếu KHÔNG flush cache trước khi lock, experiment sẽ khác thế nào?
**Rollback:** Lock tự release sau 90s.

## 🧪 Experiment 3: Kafka Consumer Lag (Notification Worker Slow)
**Runbook:** [RB-16 KafkaConsumerLagHigh](INCIDENT_RUNBOOK.md)
**Inject:** `docker pause notification-worker` (SIGSTOP) + Chạy load test.
**Kỳ vọng & Câu hỏi kiểm tra:**
- Kafka lag tăng liên tục.
- **Leading indicator:** Consumer lag bắt đầu tăng bao lâu trước khi user thấy ảnh hưởng?
- **Pause vs Stop:** `docker pause` khác `docker stop` thế nào trên dashboard?
**Rollback:** `docker unpause notification-worker`

## 🧪 Experiment 4: Cascading Failure (Payment Service Down)
**Runbook:** [RB-10 PaymentFastBurn](INCIDENT_RUNBOOK.md)
**Inject:** `docker stop payment-service` + Tạo vài orders qua UI.
**Kỳ vọng & Câu hỏi kiểm tra:**
- Order Service trả về `payment_error` nhưng không crash (Graceful Degradation).
- **Cascade pattern:** Payment chết → order-service phản ứng thế nào?
- **SLO impact:** Burn rate của API Gateway vs Payment – cái nào tăng nhanh hơn?
**Rollback:** `docker start payment-service`

## 🧪 Experiment 5: SLO Burn Rate Deep Dive (Learning Exercise)
**Runbook:** [RB-08→13 SLO Burn Rate](INCIDENT_RUNBOOK.md)
**Loại:** Learning exercise – không inject failure mới. Dùng data từ Exp 2 hoặc 4.
**Mục tiêu:** Hiểu sâu burn rate math và cách phản ứng theo team size.
- **Theory:** Error Budget = 0.5% * 30 ngày = 216 phút. Burn Rate 14.4x = hết 2% budget trong 1h.
- **Multi-Window:** Tại sao cần cả window ngắn (5m) và dài (1h)? (Để tránh alert spike thoáng qua).
- **Practice:** Mở SLO Overview, tính toán Budget Consumed thực tế dựa trên Error Rate và thời gian lỗi.

## 🧪 Experiment 6: Stock Depletion Deadlock (Logic Bug)
**Runbook:** [RB-21 HighErrorRate](INCIDENT_RUNBOOK.md)
**Inject:** `docker exec postgres psql -U app -d orders -c "UPDATE products SET stock = 0;"`
**Kỳ vọng & Câu hỏi kiểm tra:**
- Orders fail (`out_of_stock`), Auto-Restock Events = no data.
- **Design-level failure:** Đây không phải lỗi infra, mà là missing event flow (deadlock).
- **Monitoring gap:** Bạn có thể viết alert rule nào để detect trạng thái deadlock này không?
**Rollback:** `UPDATE products SET stock = 100;`

## 🧪 Experiment 7: Memory Pressure (Container Resource Limit)
**Runbook:** [RB-03 HighMemoryUsage](INCIDENT_RUNBOOK.md)
**Inject:** `docker update --memory=64m --memory-swap=64m order-service` + Chạy load test.
**Kỳ vọng & Câu hỏi kiểm tra:**
- P95 tăng (do GC pauses), sau đó OOMKilled và restart.
- **Predictive alerting:** `predict_linear()` dự đoán memory exhaustion – nó firing bao lâu trước khi OOM?
**Rollback:** `docker update --memory=0 order-service && docker restart order-service`

## 🧪 Experiment 8: DNS Cache Stale (Nginx Proxy Issue)
**Runbook:** Manual investigation (Monitoring blind spot).
**Inject:** Rebuild container `inventory-worker` (sẽ nhận IP mới) nhưng không restart `web-ui` (nginx cache IP cũ).
**Kỳ vọng & Câu hỏi kiểm tra:**
- Web UI báo Inventory Worker DOWN, nhưng `docker ps` báo healthy.
- **Misleading dashboard:** Bạn tin cái nào? Cách cross-reference?
**Fix:** `docker restart web-ui`

## 🧪 Experiment 9: Phantom Alert – SLO Burn Rate khi không có Traffic
**Runbook:** [RB-08 APIGatewayFastBurn](INCIDENT_RUNBOOK.md)
**Inject:** Stop payment → Chạy traffic (có lỗi) → Start payment → Dừng traffic và chờ.
**Kỳ vọng & Câu hỏi kiểm tra:**
- Alert vẫn firing dù service đã healthy do `rate()` không thể "dilute" error rate khi `total = 0`.
- **Stale metrics:** Tại sao `0/0` trong PromQL gây ra phantom alert?
- **Production fix:** Thêm traffic guard `rate(total[5m]) > 0` vào alert rule.

## 🧪 Experiment 10: Timezone Trap – Đọc sai Dashboard do Timezone
**Runbook:** Human error investigation.
**Inject:** Đổi Grafana timezone từ UTC sang Browser Time (UTC+7).
**Kỳ vọng & Câu hỏi kiểm tra:**
- Alert firing lúc "02:00 sáng" (UTC+7) thực chất là "19:00 tối hôm qua" (UTC).
- **UTC convention:** Tại sao production teams luôn thống nhất dùng UTC cho monitoring và logs?

## 🧪 Experiment 11: Cache-Miss Storm (Redis Dependency)
**Runbook:** [RB-22 HighLatencyP95](INCIDENT_RUNBOOK.md)
**Inject:** `docker stop redis` + Chạy traffic `browse_heavy`.
**Kỳ vọng & Câu hỏi kiểm tra:**
- Cache Hit Rate = 0%, DB query count tăng gấp 5 lần (DB amplification).
- **Cache dependency:** Redis down → service có crash không? Hay chỉ chậm hơn? (Graceful degradation).
**Rollback:** `docker start redis`

## 🧪 Experiment 12: Multi-Alert Triage (Compound Failure)
**Runbook:** Kết hợp RB-22, RB-21, RB-16, RB-12.
**Inject:** Lock DB (Exp 2) + Pause notification-worker (Exp 3) + Traffic cao.
**Kỳ vọng & Câu hỏi kiểm tra:**
- 4-5 alerts firing cùng lúc: HighLatencyP95, HighErrorRate, KafkaConsumerLagHigh, LatencyFastBurn.
- **Triage priority:** Phân nhóm alerts theo correlation. Fix DB lock trước (ảnh hưởng user trực tiếp) hay unpause worker trước?
- **Root cause vs symptom:** `HighErrorRate` là root cause hay symptom của DB lock?
**Rollback:** Kill DB lock session + `docker unpause notification-worker`

---

# Part 3: Post-Exercise Activities (Hậu kỳ & Post-Mortem)

Sau khi hoàn thành mỗi Experiment (và đã rollback), đừng tắt máy ngay. Hãy thực hành **Post-Mortem Process** (tham chiếu [Mục 0.5](#05-enhanced-post-mortem--5-whys)) bằng template sau:

```markdown
## Blameless Post-Mortem: [Tên Experiment]
**Date:** YYYY-MM-DD | **Duration:** X phút | **SEV:** [1/2/3/4]

### 1. Timeline (Dựa trên Incident Log real-time bạn đã ghi)
- [HH:MM] Inject failure
- [HH:MM] Alert fired (MTTD = X phút)
- [HH:MM] Root cause identified
- [HH:MM] Rollback executed
- [HH:MM] Alert resolved (MTTR = X phút)

### 2. Impact & Metrics
- Users/Requests affected: [Ước lượng]
- Error Budget consumed: [X%]
- MTTD: [X phút] | MTTR: [X phút]

### 3. Root Cause Analysis (5 Whys)
1. Why [triệu chứng]? → ...
2. Why ...? → ...
3. Why ...? → ...
4. Why ...? → ...
5. Why ...? → [Systemic gap]

### 4. What Went Well / What Went Poorly
- **Well:** (VD: Blackbox Exporter detect service down ngay lập tức dù không có traffic)
- **Poorly:** (VD: Mất 10 phút mới nhớ cách query pg_stat_activity để tìm lock)

### 5. Action Items (SMART)
| Action | Owner | Deadline | Priority |
|--------|-------|----------|----------|
| Thêm traffic guard vào SLO alert rule | @me | 2026-06-01 | P1 |
| Tạo cheatsheet các câu lệnh DB troubleshooting | @me | 2026-06-05 | P2 |
```

**Blameless Principles:**
- ❌ "Tôi đã quên flush cache trước khi lock DB"
- ✅ "Quy trình inject failure thiếu checklist chuẩn bị state (cache warm/cold)"
- **Rule:** Mọi "human error" đều là **system gap**. Hệ thống tốt khiến human error khó xảy ra hoặc ít impact.

---

# Part 4: Thứ tự thực hành đề xuất

| Thứ tự | Experiment | Độ khó | Kỹ năng học được |
|--------|------------|--------|------------------|
| 1 | Service Down | ⭐ | Đọc alert cơ bản, phân biệt down vs slow |
| 2 | Cascading Failure | ⭐⭐ | Hiểu dependency chain, graceful degradation |
| 3 | Kafka Consumer Lag | ⭐⭐ | Leading vs lagging indicators |
| 4 | Stock Deadlock | ⭐⭐⭐ | Design-level failure, cross-dashboard correlation |
| 5 | DB Saturation | ⭐⭐⭐ | Resource bottleneck, USE method, Trace reading |
| 6 | SLO Burn Rate (Learning) | ⭐⭐⭐ | Error budgets, burn rate math, team playbooks |
| 7 | Cache-Miss Storm | ⭐⭐⭐ | Cache dependency, DB amplification |
| 8 | DNS Cache | ⭐⭐⭐⭐ | Misleading dashboards, networking blind spots |
| 9 | Memory Pressure | ⭐⭐⭐⭐ | Infrastructure monitoring, predictive alerts |
| 10 | Phantom Alert | ⭐⭐⭐⭐ | Stale metrics, alert lifecycle, traffic guard |
| 11 | Timezone Trap | ⭐⭐ | Human error, UTC convention, cross-reference |
| 12 | Multi-Alert Triage | ⭐⭐⭐⭐⭐ | Compound failure, alert correlation, triage priority |

**Lời khuyên cuối cùng:** 
Tool không thay thế được process. Tốt nhất là master manual process (dùng lab này + Incident Log + Post-Mortem) trước khi add các tools như PagerDuty hay incident.io. Chúc bạn thực hành tốt! 🚀