# 🚨 Incident Runbook

## Mục tiêu
Tài liệu quy trình xử lý cho mọi alert trong hệ thống. Khi alert firing, mở runbook → tìm alert → follow từng bước.

**Prerequisite:** Đã hoàn thành Incident Simulation (INCIDENT_SIMULATION_GUIDE.md) → biết đọc dashboard.

## Thực hành Runbook với Experiments

Dùng bảng sau để luyện tập: chạy experiment → khi alert firing → mở runbook tương ứng → follow quy trình.

| Experiment | Inject gì | Alerts sẽ firing | Runbook |
|------------|-----------|------------------|---------|
| [Exp 1: Service Down](INCIDENT_SIMULATION_GUIDE.md#-experiment-1-service-down-health-check-failed) | `docker stop order-service` | ServiceHealthCheckFailed, ServiceNoTraces | RB-24, RB-23 |
| [Exp 2: DB Saturation](INCIDENT_SIMULATION_GUIDE.md#-experiment-2-database-saturation-high-latency) | DB table lock | HighLatencyP95, HighErrorRate, LatencyFastBurn | RB-22, RB-21, RB-12 |
| [Exp 3: Kafka Lag](INCIDENT_SIMULATION_GUIDE.md#-experiment-3-kafka-consumer-lag-notification-worker-slow) | `docker pause notification-worker` | KafkaConsumerLagHigh/Critical, ConsumerGroupDown | RB-16, RB-17, RB-18 |
| [Exp 4: Cascading Failure](INCIDENT_SIMULATION_GUIDE.md#-experiment-4-cascading-failure-payment-service-down) | `docker stop payment-service` | TargetDown, PaymentFastBurn, APIGatewayFastBurn | RB-01, RB-10, RB-08 |
| [Exp 5: Burn Rate](INCIDENT_SIMULATION_GUIDE.md#-experiment-5-slo-burn-rate-deep-dive-learning-exercise) | Dùng data từ Exp 2/4 | (learning — không inject mới) | RB-08→13 |
| [Exp 6: Stock Deadlock](INCIDENT_SIMULATION_GUIDE.md#-experiment-6-stock-depletion-deadlock-logic-bug) | Set stock = 0 | HighErrorRate | RB-21 |
| [Exp 7: Memory Pressure](INCIDENT_SIMULATION_GUIDE.md#-experiment-7-memory-pressure-container-resource-limit) | Memory limit 64m | HighMemoryUsage, HighLatencyP95 | RB-03, RB-06, RB-22 |
| [Exp 8: DNS Cache](INCIDENT_SIMULATION_GUIDE.md#-experiment-8-dns-cache-stale-nginx-proxy-issue) | Rebuild container | Không có alert tương ứng | Manual investigation |
| [Exp 9: Phantom Alert](INCIDENT_SIMULATION_GUIDE.md#-experiment-9-phantom-alert--slo-burn-rate-khi-không-có-traffic) | Stop payment → run traffic → start payment → chờ | APIGatewayFastBurn (stale) | RB-08 (Step 0) |
| [Exp 10: Timezone Trap](INCIDENT_SIMULATION_GUIDE.md#-experiment-10-timezone-trap--đọc-sai-dashboard-do-timezone) | Đổi Grafana timezone | Không inject failure | Investigation practice |
| [Exp 11: Cache-Miss Storm](INCIDENT_SIMULATION_GUIDE.md#-experiment-11-cache-miss-storm-redis-dependency) | `docker stop redis` | HighLatencyP95 (có thể) | RB-22 |
| [Exp 12: Multi-Alert Triage](INCIDENT_SIMULATION_GUIDE.md#-experiment-12-multi-alert-triage-compound-failure) | DB lock + pause worker | HighLatencyP95, HighErrorRate, KafkaConsumerLagHigh, LatencyFastBurn | RB-22, RB-21, RB-16, RB-12 |

## Severity → Action Mapping

| Severity | Burn Window | Response Time | Action | Notification |
|----------|-------------|---------------|--------|--------------|
| critical | fast | < 15 phút | Page on-call, bắt đầu xử lý ngay | Telegram/PagerDuty |
| warning | slow | < 4 giờ | Tạo ticket, xử lý trong ngày | Slack/Email |
| none | — | — | Watchdog — chỉ alert khi RESOLVED | — |

## Escalation Matrix

Áp dụng cho tất cả critical alerts. Mỗi runbook RB critical bên dưới sẽ tham chiếu bảng này.

| Điều kiện | Escalate tới | Liên hệ |
|-----------|--------------|---------|
| Critical alert chưa resolve sau 15 phút | Team Lead | Slack/Telegram |
| Critical alert chưa resolve sau 30 phút | Engineering Manager | Phone call |
| Nghi ngờ data breach / security issue | Security Team | #security-incidents |
| Ảnh hưởng revenue (Payment failures) | Finance + PM | @finance-oncall |
| Cần thông báo khách hàng | Support Lead | @support-lead |
| Không xác định được root cause sau 45 phút | Senior Engineer / Architect | Phone call |

**Nguyên tắc escalation:**
- Escalate sớm, không chờ hết thời gian. Nếu cảm thấy stuck → escalate ngay.
- Escalation không phải thất bại — đó là việc đảm bảo incident được xử lý đúng người.
- Ghi lại thời điểm escalation trong incident timeline.

## Alert Inventory

| # | Alert | Severity | Category | Source |
|---|-------|----------|----------|--------|
| 1 | TargetDown | critical | Infrastructure | alert_rules.yml |
| 2 | HighCpuUsage | warning | Infrastructure | alert_rules.yml |
| 3 | HighMemoryUsage | warning | Infrastructure | alert_rules.yml |
| 4 | HighDiskUsage | warning | Infrastructure | alert_rules.yml |
| 5 | DiskWillFillIn4Hours | warning | Predictive | alert_rules.yml |
| 6 | MemoryWillExhaustIn2Hours | warning | Predictive | alert_rules.yml |
| 7 | Watchdog | none | Meta | alert_rules.yml |
| 8 | APIGatewayFastBurn | critical | SLO | alert_rules.yml |
| 9 | APIGatewaySlowBurn | warning | SLO | alert_rules.yml |
| 10 | PaymentFastBurn | critical | SLO | alert_rules.yml |
| 11 | PaymentSlowBurn | warning | SLO | alert_rules.yml |
| 12 | APIGatewayLatencyFastBurn | critical | SLO | alert_rules.yml |
| 13 | APIGatewayLatencySlowBurn | warning | SLO | alert_rules.yml |
| 14 | KafkaExporterDown | critical | Kafka | kafka_alert_rules.yml |
| 15 | KafkaTopicUnderReplicated | warning | Kafka | kafka_alert_rules.yml |
| 16 | KafkaConsumerLagHigh | warning | Kafka | kafka_alert_rules.yml |
| 17 | KafkaConsumerLagCritical | critical | Kafka | kafka_alert_rules.yml |
| 18 | KafkaConsumerGroupDown | critical | Kafka | kafka_alert_rules.yml |
| 19 | NotificationWorkerHighErrorRate | warning | Worker | kafka_alert_rules.yml |
| 20 | InventoryWorkerHighErrorRate | warning | Worker | kafka_alert_rules.yml |
| 21 | HighErrorRate | warning | Application | tracing_alert_rules.yml |
| 22 | HighLatencyP95 | warning | Application | tracing_alert_rules.yml |
| 23 | ServiceNoTraces_* | critical | Application | tracing_alert_rules.yml |
| 24 | ServiceHealthCheckFailed | critical | Infrastructure | alert_rules.yml |

---

# Part 0: Incident Response Toolkit

> Dùng phần này **ngay khi alert firing** — trước khi mở runbook cụ thể.
> Các framework chi tiết hơn (Roles, 5 Whys, On-Call Practices) xem `INCIDENT_SIMULATION_GUIDE.md` Part 0.

## 0.1 Quick Severity Assessment

Burn-rate severity (critical/warning) đã có trong alert labels. Nhưng để quyết định **quy mô response**, trả lời nhanh 5 câu này:

| Câu hỏi | Nếu YES → |
|---------|-----------|
| 1. Toàn bộ users mất service chính? | Upgrade lên SEV-1 (page VP Eng) |
| 2. Ảnh hưởng revenue trực tiếp (payment/checkout)? | Notify Finance + PM ngay |
| 3. Có data loss / corruption? | SEV-1, không rollback data migrations |
| 4. Nghi ngờ security breach? | Page Security team, bypass normal flow |
| 5. Vi phạm SLA contractual với customer? | Escalate Support Lead + Legal |

**Solo engineer rule:** Nếu trả lời YES từ 2 câu trở lên → escalate Team Lead **ngay lập tức**, không chờ 15 phút.

## 0.2 Real-time Incident Log

**Mở file này NGAY KHI alert firing** — copy template vào Notion/Markdown và ghi real-time. Đừng tin vào trí nhớ lúc 3 AM.

```markdown
# Incident Log — [Tên incident ngắn]
**Start:** YYYY-MM-DD HH:MM UTC
**SEV ước lượng:** [1/2/3/4]
**Alert(s):** [tên alerts]
**IC:** [Tên bạn]

## Timeline (ghi MỖI khi có action/observation mới)
- [HH:MM] 🔔 Alert fired: [tên]
- [HH:MM] 👀 Ack alert, bắt đầu investigate
- [HH:MM] 🔍 Check [dashboard] → thấy [observation]
- [HH:MM] 🤔 Hypothesis: [giả thuyết]
- [HH:MM] 🎯 Decision: [action] vì [reason]
  - Considered: [alternative]
- [HH:MM] ⚡ Executed: [kết quả]
- [HH:MM] ✅ Alert resolved

## Decisions Log
| Time | Decision | Reason | Alternative considered |
|------|----------|--------|----------------------|
| HH:MM | ... | ... | ... |

## Open Questions (để follow-up post-mortem)
- [ ] ...
```

**Tại sao bắt buộc:** Post-mortem không có timeline real-time = timeline sai = action items sai = incident lặp lại.

## 0.3 Decision Framework Under Pressure

### Rollback vs Fix Forward

| Tình huống | Decision | Lý do |
|------------|----------|-------|
| Deploy mới trong 30 phút | **Rollback** | An toàn nhất, investigate sau |
| Code đã chạy > 24h | **Fix forward** | Rollback có thể gây data inconsistency |
| Unknown root cause, có thể rollback | **Rollback** | Stop the bleeding |
| Known root cause, fix đơn giản | **Fix forward** | Nhanh hơn, giữ context |
| Database schema migration | **KHÔNG rollback** | Data migration không reversible → fix forward |
| Config change (feature flag, env) | **Rollback** | Luôn reversible, zero risk |

### Stop-the-Bleeding Priority (khi panic)

Ghi nhớ thứ tự này khi áp lực cao:

1. **Stop customer impact** > Find root cause
   - User đang mất tiền → restart/mitigate trước, debug sau
2. **Mitigation (workaround)** > Perfect fix
   - Feature flag off, rate limit, fallback response
3. **Communication** > Silence
   - Update stakeholders mỗi 15 phút (SEV-1/2), dù chưa có gì mới
4. **Preserve evidence** > Clean up
   - Đừng xóa logs, đừng restart ngay nếu cần debug
   - Nhưng: preserve evidence **sau khi** đã stop impact

### Khi nào KHÔNG action?

- Alert firing nhưng **không có traffic** (phantom alert) → Check RB-08 Step 0 trước
- Alert warning, business hours, không user impact → Tạo ticket, không page
- Watchdog resolved → Page ngay (alerting pipeline broken)

---

# Part 1: Infrastructure Alerts

## 🔴 RB-01: TargetDown
**Severity:** critical | **Response:** < 15 phút

**Nghĩa là gì:** Prometheus không scrape được metrics từ target. Service hoặc exporter có thể down.

**Triage:**

**Bước 1: Xác định target nào down**
- Alert annotation chứa `{{ instance }}` và `{{ job }}`
- Mở Alerting Overview dashboard để xem chi tiết

**Bước 2: Kiểm tra container**
```bash
ssh <vm>
docker ps -a | grep <service-name>
# Nếu container Exited → xem exit code
docker logs <service-name> --tail 50
```

**Bước 3: Phân loại**
- Container Exited → `docker start <service-name>`
- Container Running nhưng port không respond → `docker restart <service-name>`
- Container OOMKilled → check HighMemoryUsage, tăng memory limit
- VM unreachable → kiểm tra network/SSH

**Bước 4: Verify recovery**
- Chờ 1-2 phút, check Alerting Overview → alert chuyển RESOLVED
- Check Unified Overview → RPS của service hồi phục

**Dashboard path:** Alerting Overview → Unified Overview → Docker Containers

**Phân biệt với:** HighErrorRate (service running nhưng trả lỗi) vs TargetDown (service không respond)

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Target down > 15 phút → Team Lead.

## 🟡 RB-02: HighCpuUsage
**Severity:** warning | **Response:** < 4 giờ

**Nghĩa là gì:** CPU usage > 80% trên VM trong 5 phút liên tục.

**Triage:**

**Bước 1: Xác định VM nào**
- Alert annotation: `{{ instance }}`
- Mở Node Overview dashboard, filter theo VM

**Bước 2: Xác định process nào chiếm CPU**
```bash
ssh <vm>
top -bn1 | head -20
# Hoặc xem per-container
docker stats --no-stream
```

**Bước 3: Phân loại**
- Application container (api-gateway, order-service...)
  - Check traffic: có đang load test không?
  - Nếu traffic bình thường mà CPU cao → có thể memory leak gây GC pressure
- System process (node-exporter, cadvisor...)
  - Thường tự giảm, monitor thêm 15 phút
- Prometheus/Grafana
  - Kiểm tra query complexity, scrape interval

**Bước 4: Mitigation**
- Nếu do traffic spike → scale hoặc rate limit
- Nếu do bug → restart service, investigate later
- Nếu sustained → tạo ticket để optimize

**Dashboard path:** Node Overview → Docker Containers (CPU panel)

## 🟡 RB-03: HighMemoryUsage
**Severity:** warning | **Response:** < 4 giờ

**Triage:**

**Bước 1:**
```bash
ssh <vm>
free -h
# Xem memory per container
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

**Bước 2: Phân loại**
- Gradual increase → memory leak → restart container + tạo ticket
- Sudden spike → traffic burst → check request rate
- Prometheus/Loki → data retention quá lớn → giảm retention hoặc tăng RAM

**Bước 3: Quick fix**
```bash
docker restart <highest-memory-container>
```

**Dashboard path:** Node Overview → Docker Containers (Memory panel)

## 🟡 RB-04: HighDiskUsage
**Severity:** warning | **Response:** < 4 giờ

**Triage:**

**Bước 1:**
```bash
ssh <vm>
df -h
# Tìm directory chiếm nhiều nhất
du -sh /var/lib/docker/* | sort -rh | head -10
```

**Bước 2: Phân loại**
- `/var/lib/docker` → Docker images/volumes
  - `docker system prune -f`
  - `docker volume prune -f`
- Prometheus data → `/var/lib/prometheus`
  - Giảm retention: `--storage.tsdb.retention.time`
- Loki data → log volume quá lớn
  - Check Log Volume dashboard → service nào log nhiều nhất
  - Giảm log level hoặc tăng retention policy

## 🟡 RB-05: DiskWillFillIn4Hours
**Severity:** warning | **Response:** < 2 giờ

**Nghĩa là gì:** Dựa trên trend 24 giờ qua, disk sẽ đầy trong 4 giờ tới.

**Triage:** Tương tự RB-04 nhưng khẩn cấp hơn → phải hành động trước khi disk full.

> ⚠️ **Nếu disk full:**
> - Prometheus mất khả năng ghi metrics → monitoring bị mù
> - Loki mất khả năng ghi logs → không debug được
> - Docker containers không thể write → crash

**Quick fix nếu < 1 giờ:**
```bash
docker system prune -af  # Xóa tất cả unused images
# Nếu vẫn không đủ → xóa old Prometheus data
# rm -rf /path/to/prometheus/data/wal/*.tmp
```

## 🟡 RB-06: MemoryWillExhaustIn2Hours
**Severity:** warning | **Response:** < 1 giờ

**Triage:** Tương tự RB-03 nhưng khẩn cấp hơn.

**Quick fix:**
```bash
# Restart service chiếm memory nhiều nhất
docker stats --no-stream --format "{{.Name}}\t{{.MemPerc}}" | sort -k2 -rn | head -5
docker restart <top-consumer>
```

## 🟢 RB-07: Watchdog
**Severity:** none | **Response:** Chỉ khi RESOLVED

**Nghĩa là gì:** Alert này luôn firing. Nếu nó chuyển RESOLVED → alerting pipeline bị hỏng.

**Khi Watchdog RESOLVED:**

**Bước 1: Kiểm tra Prometheus**
```bash
docker logs prometheus --tail 20
curl http://prometheus:9090/-/healthy
```

**Bước 2: Kiểm tra Alertmanager**
```bash
docker logs alertmanager --tail 20
curl http://alertmanager:9093/-/healthy
```

**Bước 3: Kiểm tra network giữa Prometheus → Alertmanager**
```bash
docker exec prometheus wget -q -O- http://alertmanager:9093/-/healthy
```

---

# Part 2: SLO Burn Rate Alerts

> **Tham khảo:** INCIDENT_SIMULATION_GUIDE.md → Experiment 5 cho theory chi tiết.

## 🔴 RB-08: APIGatewayFastBurn
**Severity:** critical | **Response:** < 15 phút | **Burn Rate:** > 14.4x

**Nghĩa là gì:** API Gateway đang tiêu error budget cực nhanh. Nếu tiếp tục, hết 2% budget trong 1 giờ.

**Triage:**

**Bước 0: Kiểm tra phantom alert (NO TRAFFIC)**
- Unified Overview → tất cả RPS = 0?
- Nếu **KHÔNG có traffic:**
  - Alert có thể firing từ stale data (rate() chưa decay)
  - Verify service healthy: `curl` health endpoints
  - Nếu service healthy + no traffic → phantom alert
  - Action: silence alert + ghi chú "phantom — no traffic"
  - Traffic guard đã được thêm vào alert rule để tránh tái phát
- Nếu **CÓ traffic** → tiếp tục Bước 1

**Bước 1: Xác nhận burn rate**
- SLO Overview → API Gateway Burn Rate panel
- Cả Fast(5m) **VÀ** Fast(1h) đều > 14.4x?
- Nếu chỉ 5m > 14.4x mà 1h < 14.4x → spike thoáng qua, monitor thêm
- Kiểm tra timezone: Grafana đang hiển thị UTC hay local time?

**Bước 2: Xác định nguyên nhân**
- App Performance → API Gateway section
- Error rate tăng ở endpoint nào?
- Tracing → tìm trace có error → xem error message

**Bước 3: Phân loại root cause**
- Downstream service down (payment, order)
  - Check Unified Overview → service nào RPS = 0
  - Follow RB-01 cho service đó
- Database issue
  - App Performance → duration spike
  - Check DB connection pool, slow queries
- Code bug (new deployment)
  - Check deploy annotations trên SLO Overview
  - Rollback: redeploy previous version

**Bước 4: Verify**
- Burn rate giảm xuống < 14.4x
- Availability gauge hồi phục > 99.5%
- Error Budget không tiếp tục giảm

**Escalation:**
- Burn rate > 14.4x sau 15 phút xử lý → thông báo team lead
- Burn rate > 14.4x sau 30 phút → escalate engineering manager

## 🟡 RB-09: APIGatewaySlowBurn
**Severity:** warning | **Response:** < 4 giờ | **Burn Rate:** > 3x

**Nghĩa là gì:** API Gateway đang có degradation nhỏ nhưng kéo dài. Nếu tiếp tục, hết 10% budget trong 6 giờ.

**Triage:**

**Bước 1: Xác nhận**
- SLO Overview → cả Slow(30m) **VÀ** Slow(6h) > 3x

**Bước 2: Xác định pattern**
- Latency tăng nhẹ? → DB slow, cache miss
- Error rate tăng nhẹ? → Intermittent failures, retry storms
- Cả hai? → Resource contention

**Bước 3: Action**
- Tạo ticket với context:
  - Burn rate hiện tại
  - Thời điểm bắt đầu (nhìn trend chart)
  - Error Budget remaining
- Fix trong ngày hoặc sprint hiện tại

## 🔴 RB-10: PaymentFastBurn
**Severity:** critical | **Response:** < 15 phút

**Nghĩa là gì:** Payment success rate đang giảm nghiêm trọng. Ảnh hưởng trực tiếp đến doanh thu.

**Triage:**

**Bước 1: Xác nhận**
- SLO Overview → Payment Burn Rate panel

**Bước 2: Xác định nguyên nhân**
- App Performance → Payment Service section
- `payments_total{status="failed"}` tăng?
- Tracing → payment span có error gì?

**Bước 3: Common causes**
- Payment service container down → `docker start payment-service`
- Payment service timeout → check upstream dependency
- Database connection exhausted → check connection pool

> ⚠️ **Payment failure = MẤT TIỀN TRỰC TIẾP**
> - Ưu tiên cao nhất, không chỉ mất data
> - Rollback/restart ngay nếu không rõ root cause

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Payment failure = revenue impact → escalate Finance + PM ngay khi xác nhận. Chưa resolve sau 15 phút → Engineering Manager.

## 🟡 RB-11: PaymentSlowBurn
**Severity:** warning | **Triage:** Tương tự RB-09 nhưng focus payment service.

## 🔴 RB-12: APIGatewayLatencyFastBurn
**Severity:** critical | **Response:** < 15 phút

**Nghĩa là gì:** Phần lớn requests vượt 500ms. Service hoạt động nhưng quá chậm → user trải nghiệm tệ.

**Triage:**

**Bước 1: Xác nhận**
- SLO Overview → Latency Burn Rate panel
- Latency Compliance gauge: bao nhiêu % requests < 500ms?

**Bước 2: So sánh với Availability**
- Availability OK + Latency NOT OK
  - Requests thành công nhưng chậm
  - DB slow, CPU contention, network latency
- Availability NOT OK + Latency NOT OK
  - Requests vừa chậm vừa lỗi
  - Likely resource exhaustion

**Bước 3: Drill down**
- App Performance → P95/P99 duration
- Tracing → sort by duration → longest trace
- Xem span nào chiếm thời gian nhiều nhất (db? external call? processing?)

**Bước 4: Common fixes**
- DB slow → kill long-running queries, check missing indexes
- CPU pressure → restart container hoặc scale
- Memory pressure → GC pauses → restart + increase memory limit

**Bài học:** Alert này bắt được vấn đề mà Availability SLO bỏ sót — hệ thống 100% available nhưng 100% chậm.

## 🟡 RB-13: APIGatewayLatencySlowBurn
**Severity:** warning | **Triage:** Tương tự RB-12 nhưng ít khẩn cấp hơn. Tạo ticket.

---

# Part 3: Kafka & Worker Alerts

## 🔴 RB-14: KafkaExporterDown
**Severity:** critical | **Response:** < 15 phút

**Nghĩa là gì:** Không scrape được Kafka metrics. Monitoring bị mù cho event pipeline.

- Bước 1: `docker ps | grep kafka-exporter`
- Bước 2: `docker logs kafka-exporter --tail 20`
- Bước 3: `docker restart kafka-exporter`
- Bước 4: Nếu vẫn fail → kiểm tra Kafka broker: `docker logs kafka --tail 20`

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Kafka exporter down = monitoring blind cho event pipeline. Chưa resolve sau 15 phút → Team Lead.

## 🟡 RB-15: KafkaTopicUnderReplicated
**Severity:** warning

**Nghĩa là gì:** Partition không có đủ replicas. Data durability at risk.

**Bước 1: Xác định topic/partition**
- Alert annotation chứa `{{ topic }}` và `{{ partition }}`

**Bước 2: Check Kafka broker health**
```bash
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic <topic>
```

**Bước 3: Nếu single-node (lab environment)**
- Replication factor = 1 → alert này expected
- Có thể suppress nếu không relevant

## 🟡 RB-16: KafkaConsumerLagHigh (lag > 100)
**Severity:** warning | **Response:** < 4 giờ

**Bước 1: Xác định consumer group**
- Kafka Overview dashboard → Consumer Lag panel
- Group nào lag: notification-workers? inventory-workers?

**Bước 2: Check worker health**
```bash
docker ps | grep <worker-name>
docker logs <worker-name> --tail 20
```

**Bước 3: Phân loại**
- Worker running, lag tăng chậm → processing chậm → check downstream (DB, external API)
- Worker running, lag tăng nhanh → produce rate > consume rate → cần scale workers
- Worker restarting → check OOM, error logs

## 🔴 RB-17: KafkaConsumerLagCritical (lag > 1000)
**Severity:** critical | **Response:** < 15 phút

**Triage:** Tương tự RB-16 nhưng khẩn cấp — backlog rất lớn.

> ⚠️ **Lag > 1000 = hàng nghìn events chưa xử lý**
> - Notifications bị delay
> - Inventory updates bị delay
> - Business impact: customers không nhận được confirmation

**Quick fix:** `docker restart <worker-name>`

Nếu vẫn lag → check produce rate trên Kafka Overview
- Nếu produce rate cũng cao → traffic spike, cần scale

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Lag > 1000 kéo dài > 15 phút → Team Lead. Lag vẫn tăng sau restart → Engineering Manager.

## 🔴 RB-18: KafkaConsumerGroupDown
**Severity:** critical | **Response:** < 15 phút

**Bước 1: Xác định group**
- Alert: `{{ consumergroup }}`

**Bước 2: Check worker container**
```bash
docker ps -a | grep <worker>
# Nếu Exited → docker start <worker>
# Nếu Running → docker restart <worker>
```

**Bước 3: Verify**
- Kafka Overview → consumer group members > 0
- Consumer lag bắt đầu giảm (catch-up)

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Consumer group down > 15 phút → Team Lead.

## 🟡 RB-19/20: Worker High Error Rate
**Severity:** warning | **Applies to:** notification-worker, inventory-worker
 > **⚠️ Note cho Exp 3**: Alert NotificationWorkerHighErrorRate có thể firing KHI worker bị pause vì điều kiện: consumed == 0 AND lag > 0. Đây KHÔNG phải error thực sự — worker chỉ đang bị đóng băng. Sau khi unpause, alert sẽ tự resolve.  

**Bước 1: Check error logs**
```bash
docker logs <worker-name> --tail 50 | grep -i error
```

**Bước 2: Common causes**
- DB connection failed → check postgres container
- Kafka deserialization error → check message format
- Downstream service timeout → check dependency health

**Bước 3: Fix**
- Transient error → `docker restart <worker>`
- Persistent error → check code/config, tạo ticket

---

# Part 4: Application Alerts (Tracing-based)

## 🟡 RB-21: HighErrorRate
**Severity:** warning | **Source:** Span metrics

**Nghĩa là gì:** Service có > 10% requests trả về error (từ distributed tracing data).

**Bước 1: Xác định service**
- Alert: `{{ service_name }}`

**Bước 2: Drill down**
- App Performance → service section → error rate panel
- Tracing → filter service + status=error → xem error message
- Docker Logs → filter container → tìm stack trace

**Bước 3: So sánh với SLO alerts**
- HighErrorRate firing + Burn Rate alert **KHÔNG** firing
  - Error rate cao nhưng chưa đủ để ảnh hưởng SLO budget
  - Tạo ticket, fix trong sprint
- HighErrorRate firing + Burn Rate alert **CÙNG** firing
  - Nghiêm trọng → follow RB-08/10/12

## 🟡 RB-22: HighLatencyP95
**Severity:** warning | **Source:** Span metrics

**Bước 1: Xác định service**
- Alert: `{{ service_name }}`
- App Performance → P95 duration panel

**Bước 2: Tìm bottleneck qua Tracing**
- Sort traces by duration (longest first)
- Xem span nào chậm nhất:
  - `db.query` span chậm → DB issue
  - `http.request` span chậm → downstream service issue
  - `processing` span chậm → CPU/memory issue

**Bước 3: Cross-reference**
- Docker Containers → CPU/Memory cho container đó
- Nếu CPU > 80% → resource contention (xem RB-02)

## 🔴 RB-23: ServiceNoTraces_*
**Severity:** critical | **Condition:** Chỉ fire khi traffic-gen đang chạy

**Bước 1: Confirm traffic-gen đang chạy**
```bash
docker ps | grep traffic-gen
```

**Bước 2: Check service container**
```bash
docker ps | grep <service-name>
docker logs <service-name> --tail 20
```

**Bước 3: Nếu container running nhưng không có traces**
- OTel SDK issue → check OTel Collector logs
- Network issue → container có reach được otel-collector không?
```bash
docker exec <service> wget -q -O- http://otel-collector:4318/v1/traces
```

## 🔴 RB-24: ServiceHealthCheckFailed
**Severity:** critical | **Response:** < 15 phút

**Nghĩa là gì:** Blackbox Exporter probe `/health/live` thất bại. Service không phản hồi hoặc không trả HTTP 200. Đây là active probing → detect service down mà không phụ thuộc vào traffic.

**Triage:**

**Bước 1: Xác định service nào bị**
- Alert annotation: instance = URL bị fail (ví dụ: `http://192.168.100.57:5001/health/live`)
- Map port → service:
  - 5000 = api-gateway
  - 5001 = order-service
  - 5002 = payment-service
  - 5004 = notification-worker
  - 5005 = inventory-worker

**Bước 2: Kiểm tra container**
```bash
ssh 192.168.100.57
docker ps -a | grep <service-name>
docker logs <service-name> --tail 30
```

**Bước 3: Phân loại**
- Container Exited → `docker start <service-name>`
- Container Running → Port có listen không? `curl localhost:<port>/health/live`
- Container OOMKilled → Kiểm tra HighMemoryUsage alert, tăng memory limit
- Network unreachable → Kiểm tra firewall / docker network

**Bước 4: Verify recovery**
- Chờ 1-2 phút, kiểm tra Prometheus targets → blackbox job healthy
- Alerting Overview → alert chuyển RESOLVED
- Unified Overview → RPS hồi phục (nếu có traffic)

**Dashboard path:** Alerting Overview → Docker Containers (restart count) → Unified Overview

**Phân biệt với:**
- `TargetDown` → Prometheus scrape target down (OTel Collector, node-exporter...)
- `ServiceHealthCheckFailed` → Application service health endpoint down
- `ServiceNoTraces` → Service chạy nhưng không produce traces (cần traffic-gen)

**Escalation:** Xem [Escalation Matrix](#escalation-matrix). Service health check failed > 15 phút → Team Lead.

---

# Part 5: Incident Response Templates

## Basic Incident Report

Sử dụng template cơ bản này cho SEV-3/4 hoặc incidents đơn giản:

```markdown
## Incident Report

**Date:** YYYY-MM-DD HH:MM
**Duration:** X phút (từ alert firing → resolved)
**Severity:** critical / warning
**Alert(s):** [tên alert]

### Timeline
- HH:MM — Alert firing, nhận notification
- HH:MM — Bắt đầu triage
- HH:MM — Xác định root cause: [mô tả]
- HH:MM — Apply fix: [mô tả]
- HH:MM — Alert resolved, metrics hồi phục

### Metrics
- MTTD (Mean Time to Detect): X phút
- MTTR (Mean Time to Recover): X phút
- Error Budget consumed: X%

### Root Cause
[1-2 câu mô tả nguyên nhân gốc]

### Action Items
- [ ] [Fix] Mô tả fix đã apply
- [ ] [Prevent] Gì cần làm để ngăn tái diễn
- [ ] [Detect] Runbook/alert cần update gì
- [ ] [Follow-up] Deadline cho action items: ___
```

## Enhanced Post-Mortem Template (cho SEV-1/2)

Dùng cho incidents nghiêm trọng hoặc khi cần phân tích sâu. Tham chiếu `INCIDENT_SIMULATION_GUIDE.md` §0.5 để hiểu sâu hơn về 5 Whys và Blameless Principles.

```markdown
## Blameless Post-Mortem

**Date:** YYYY-MM-DD | **Duration:** X phút | **SEV:** [1/2/3/4]
**Incident Commander:** [Tên]
**Participants:** [List]

### Executive Summary
[2-3 câu tóm tắt: gì xảy ra, impact, resolution]

### Impact
- Users affected: X
- Revenue impact: $X (nếu có)
- Error Budget consumed: X%
- Customer complaints: X

### Timeline (dựa trên Incident Log real-time)
- [HH:MM UTC] — Inject / Trigger event
- [HH:MM UTC] — Alert fired (MTTD = X phút)
- [HH:MM UTC] — Investigating started
- [HH:MM UTC] — Root cause identified
- [HH:MM UTC] — Mitigation applied
- [HH:MM UTC] — Alert resolved (MTTR = X phút)
- [HH:MM UTC] — Monitoring confirmed recovery

### Root Cause Analysis (5 Whys)
1. **Why** [triệu chứng]? → [answer]
2. **Why** [answer từ #1]? → [answer]
3. **Why** [answer từ #2]? → [answer]
4. **Why** [answer từ #3]? → [answer]
5. **Why** [answer từ #4]? → **[Systemic gap]**

### What Went Well
- [Điều tích cực #1 — VD: MTTD < 1 phút nhờ Blackbox Exporter]
- [Điều tích cực #2 — VD: Runbook RB-XX có steps đúng]
- [Điều tích cực #3]

### What Went Poorly (không blame cá nhân)
- [Gap #1 — VD: Mất 10 phút nhớ cách query pg_stat_activity]
- [Gap #2 — VD: Không có cheatsheet commands DB troubleshooting]
- [Gap #3]

### Action Items (SMART)
| # | Action | Owner | Deadline | Priority | Status |
|---|--------|-------|----------|----------|--------|
| 1 | [Fix] ... | @alice | YYYY-MM-DD | P1 | Open |
| 2 | [Prevent] ... | @bob | YYYY-MM-DD | P1 | Open |
| 3 | [Detect] ... | @carol | YYYY-MM-DD | P2 | Open |

### Lessons Learned
[1-2 bài học chính để chia sẻ với team]

### Follow-up Schedule
- [ ] 48h: Post-mortem meeting (blameless)
- [ ] 1 week: Check-in action items progress
- [ ] 1 month: Verify action items completed
- [ ] Quarterly: Reliability review — xu hướng incidents
```

### Blameless Principles (nhắc nhở)

- ❌ "Alice deploy code gây crash"
- ✅ "Deploy process không có pre-deployment validation"
- ❌ "Bob không đọc alert sớm"
- ✅ "Alert routing không đến đúng channel lúc 3 AM"

**Rule:** Mọi "human error" đều là **system gap**. Hệ thống tốt khiến human error khó xảy ra hoặc ít impact.

## Communication Templates

Sử dụng 3 templates sau để thông báo trong quá trình xử lý incident:

### Initial Notification (gửi ngay khi bắt đầu xử lý)

```
🚨 INCIDENT: [Mô tả ngắn]

Severity: [critical / warning]
Status: Investigating
Impact: [Mô tả ảnh hưởng — bao nhiêu % users, feature nào]
Start Time: [HH:MM UTC]
On-call: [Tên người xử lý]

Đang investigate, update tiếp trong 15 phút.
Channel: #incident-YYYY-MM-DD
```

### Status Update (gửi mỗi 15-30 phút cho critical, 1-2 giờ cho warning)

```
🔄 UPDATE: [Mô tả ngắn]

Status: [Investigating / Mitigating / Monitoring]
Impact: [Cập nhật — tăng/giảm/không đổi]
Duration: [X phút kể từ khi bắt đầu]

Actions Taken:
- [Hành động 1]
- [Hành động 2]

Next Steps:
- [Việc sẽ làm tiếp]

ETA to Resolution: [~X phút / Chưa xác định]
```

### Resolution Notification (gửi khi incident resolved)

```
✅ RESOLVED: [Mô tả ngắn]

Duration: [X phút]
Impact: [Tổng kết — bao nhiêu requests/users bị ảnh hưởng]
Root Cause: [1-2 câu]
Resolution: [Đã làm gì để fix]

Metrics:
- MTTD: [X phút]
- MTTR: [X phút]
- Error Budget consumed: [X%]

Follow-up:
- Post-mortem scheduled: [Ngày]
- Action items: [Link tới ticket/issue]
```

---

# Part 6: Quick Reference

## Commands hay dùng khi incident

```bash
# Container status
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Resource usage
docker stats --no-stream

# Logs (last 50 lines)
docker logs <container> --tail 50

# Logs (follow real-time)
docker logs <container> -f --since 5m

# Restart service
docker restart <container>

# Check Prometheus targets
curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check firing alerts
curl -s http://prometheus:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing") | {alert: .labels.alertname, severity: .labels.severity}'

# Check Kafka consumer lag
docker exec kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups

# DB connections
docker exec postgres psql -U app -d orders -c "SELECT count(*) FROM pg_stat_activity;"

# Kill long-running DB queries (khi DB saturation)
docker exec postgres psql -U app -d orders -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'active' AND query NOT LIKE '%pg_stat%';"

# Check container OOM/restart count
docker inspect --format='{{.RestartCount}}' <container>
docker inspect --format='{{.State.OOMKilled}}' <container>
```

## Dashboard shortcuts

| Situation | Dashboard | What to look for |
|-----------|-----------|------------------|
| Alert firing | Alerting Overview | Severity, duration, which alerts |
| Service health | Unified Overview | RPS, error rate, latency per service |
| Deep dive per service | App Performance | RED metrics, business KPIs |
| SLO/Budget | SLO Overview | Burn rate, error budget remaining |
| Infrastructure | Docker Containers | CPU, memory, network per container |
| Event pipeline | Kafka Overview | Produce/consume rate, consumer lag |
| Find root cause | Tracing (Tempo) | Trace waterfall, error spans |
| Log investigation | Docker Logs | Error logs, stack traces |