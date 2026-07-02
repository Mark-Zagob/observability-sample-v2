# Blameless Post-Mortem Template — AWS Chaos Experiments

> **Hướng dẫn sử dụng:**
> 1. Copy file này thành `XX-AWS-<Tên-ngắn-gọn>.md` (VD: `02-AWS-IAM-Blackhole.md`)
> 2. Điền từng section theo thứ tự — Section 1 ghi **REAL-TIME** trong lúc drill, Section 2 ghi **SAU KHI** drill xong
> 3. Tham khảo ví dụ mẫu:
>    - On-premises: [`01-GOLDEN-EXAMPLE-DB-Saturation.md`](../on-premises/post-mortems/01-GOLDEN-EXAMPLE-DB-Saturation.md)
>    - On-premises: [`ORDER-SERVICE-DOWN-BLAMELESS-Post-Morterm.md`](../on-premises/post-mortems/ORDER-SERVICE-DOWN-BLAMELESS-Post-Morterm.md)
> 4. Chaos Playbook: [`docs/AWS_CHAOS_PLAYBOOK.md`](./AWS_CHAOS_PLAYBOOK.md)

---

> **⚠️ Sự khác biệt giữa On-Premises và AWS Post-Mortem:**
>
> | Aspect | On-Premises (Docker Compose) | AWS (ECS Fargate) |
> |---|---|---|
> | **Inject failure** | `docker stop`, `docker exec` | `aws iam`, `aws ec2`, `aws ecs`, Terraform |
> | **Observe** | Grafana dashboards, Prometheus | CloudWatch Alarms, EventBridge, Telegram |
> | **Diagnose** | `docker ps`, `docker logs` | `aws ecs describe-services`, CloudWatch Logs |
> | **Resolve** | `docker start`, `docker restart` | `terraform apply`, `aws iam attach-role-policy` |
> | **Verify** | Grafana → RPS recovered | `aws cloudwatch describe-alarms` → state OK |
> | **Key learning** | Observability stack (OTel, Grafana) | AWS-native monitoring + IaC drift detection |

---

## 📋 Section 1: Incident Log (Ghi REAL-TIME trong lúc drill)

> **Rule:** Ghi NGAY khi nó xảy ra. Đừng tin trí nhớ. Mỗi dòng = 1 timestamp + 1 action/observation.

```yaml
---
incident_id: INC-YYYYMMDD-XXX
date: YYYY-MM-DD
experiment: "Exp X: <Tên experiment từ AWS_CHAOS_PLAYBOOK.md>"
severity: SEV-X
status: draft  # draft | reviewing | published
environment: AWS ECS Fargate (ap-southeast-2)
tags: [experiment-X, <service-name>, <failure-type>]
impact:
  services_affected: [<service-1>, <service-2>]
  users_affected: "N/A (lab)"
  error_budget_consumed: "X%"
metrics:
  mttd_minutes: X.X
  mttr_minutes: X.X
---
```

### Experiment Context

| Field | Value |
|---|---|
| **Experiment** | [Exp X: <Tên>](./AWS_CHAOS_PLAYBOOK.md#-experiment-x-tên) |
| **Hypothesis** | `<Ghi hypothesis TRƯỚC KHI inject — đây là scientific method>` |
| **Blast Radius** | `<Dự đoán: service nào bị, service nào KHÔNG bị>` |
| **Rollback Plan** | `<Lệnh rollback cụ thể — copy từ Phase 4 trong Playbook>` |

### SEV Assessment (ghi trong 30s đầu sau khi inject)

> **AWS Context:** Trên AWS, SEV assessment khác on-premises vì có thêm yếu tố: blast radius cross-service, IAM scope, và CloudWatch alarm coverage.

- **Initial SEV:** SEV-[1/2/3/4]
  - 1. Bao nhiêu services bị ảnh hưởng? `<X/Y services>`
  - 2. Alarm nào đã fire? `<Tên alarm hoặc "Không alarm nào fire — BLIND SPOT">`
  - 3. Có data loss không? `<Có/Không — check DynamoDB/RDS/Kafka>`
  - 4. Có IAM/security implication không? `<Có/Không>`
  - 5. Blast radius có đúng như dự đoán không? `<Đúng/Sai — tại sao>`
- **Escalation decision:** `<Có/Không — lab nên ghi "nếu production thì escalate ai">`

### Timeline

> **Tip:** Copy các AWS CLI commands đã chạy vào timeline — giúp reproduce sau này.

```
- [HH:MM] 📊 Pre-flight check passed: X/X alarms OK, Telegram healthy
- [HH:MM] 💉 **INJECT:** <lệnh inject cụ thể>
  ```
  aws iam detach-role-policy --role-name ... --policy-arn ...
  ```
- [HH:MM] 👀 Check CloudWatch Alarms → <observation>
- [HH:MM] 🔔 **Alert fired:** <tên alarm> via <channel: Telegram/EventBridge>
  - MTTD = Xm Xs
- [HH:MM] 🔍 Check `aws ecs describe-services` → <observation>
  - RunningCount: X, DesiredCount: X, Events: "<last event>"
- [HH:MM] 🤔 Hypothesis #1: <giả thuyết> → CHECK → ACCEPT/REJECT
- [HH:MM] 🤔 Hypothesis #2: <giả thuyết> → CHECK → ACCEPT/REJECT
- [HH:MM] 🔍 Check CloudWatch Logs → <observation hoặc "Logs trống — container chưa start">
- [HH:MM] 🎯 **Decision:** <action> vì <reason>
  - Considered: <alternatives đã cân nhắc>
  - Risk: <risk nếu có>
- [HH:MM] ⚡ **ROLLBACK:**
  ```
  <lệnh rollback cụ thể>
  ```
- [HH:MM] 🔁 Verify recovery:
  - [ ] `aws ecs describe-services` → RunningCount = DesiredCount
  - [ ] `aws cloudwatch describe-alarms` → state OK
  - [ ] Telegram nhận "ALARM → OK" notification
- [HH:MM] ✅ **Incident resolved** (MTTR = Xm Xs)
```

### Decisions Log

| Time | Decision | Reason | Alternative considered |
|------|----------|--------|----------------------|
| HH:MM | ... | ... | ... |

### Prediction vs Reality

> **Scientific method:** So sánh hypothesis ban đầu với kết quả thực tế. Discrepancy = learning opportunity.

| Prediction (Pre-Mortem) | Reality | Match? | Learning |
|---|---|---|---|
| Alarm X sẽ fire trong ≤ 5 phút | ... | ✅/❌ | ... |
| Service Y KHÔNG bị ảnh hưởng | ... | ✅/❌ | ... |
| Rollback mất ≤ 2 phút | ... | ✅/❌ | ... |
| CloudWatch Logs sẽ có error | ... | ✅/❌ | ... |

---

## 📊 Section 2: Blameless Post-Mortem (Viết SAU drill, trong 24h)

> **Rule:** Viết khi còn nhớ. Sau 48h, chi tiết sẽ mờ. Dựa trên Incident Log ở Section 1.

### Executive Summary

> 2-3 câu: WHAT happened → IMPACT → RESOLUTION. Viết sao cho người không biết AWS cũng hiểu.

`<Viết ở đây>`

### Impact Assessment

| Metric | Value | Notes |
|---|---|---|
| **Services affected** | `<list>` | `<blast radius thực tế>` |
| **Alarms fired** | `<list hoặc "NONE — blind spot">` | `<infra vs app alarm>` |
| **Time-To-Detect (MTTD)** | `Xm Xs` | Target: ≤ 5 phút |
| **Time-To-Resolve (MTTR)** | `Xm Xs` | Target: ≤ 15 phút (chaos drill) |
| **Data loss** | `None / X records` | |
| **Terraform drift** | `Yes / No` | `<resources bị drift>` |
| **Error Budget consumed** | `X%` | `<calculation>` |

### Root Cause Analysis — 5 Whys

> **Blameless Principle:** Mỗi "Why" dẫn đến **system/process gap**, KHÔNG phải "human error".
> **AWS-specific:** Focus vào IAM, networking, monitoring gaps — không phải "tôi quên chạy lệnh".

**Why 1:** Tại sao `<triệu chứng>`?
→ `<answer>`

**Why 2:** Tại sao `<answer từ #1>`?
→ `<answer>`

**Why 3:** Tại sao `<answer từ #2>`?
→ `<answer>`

**Why 4:** Tại sao `<answer từ #3>`?
→ `<answer — nên chạm tới monitoring/alerting gap ở đây>`

**Why 5:** Tại sao `<answer từ #4>`?
→ **Systemic Gap:** `<root cause cuối cùng>`

### What Went Well

> Ghi ít nhất 2 điều. Quan trọng cho morale — chaos experiments thất bại = vẫn thành công nếu học được gì.

1. ✅ `<điều tích cực #1>`
2. ✅ `<điều tích cực #2>`
3. ✅ `<điều tích cực #3>`

### What Went Poorly (Systemic Gaps)

> **KHÔNG blame cá nhân.** Focus vào: Monitoring gap? Alarm missing? Terraform config? Runbook thiếu?

1. ⚠️ `<gap #1>` — **Gap:** `<systemic root cause>`
2. ⚠️ `<gap #2>` — **Gap:** `<systemic root cause>`
3. ⚠️ `<gap #3>` — **Gap:** `<systemic root cause>`

### Monitoring Gap Analysis

> **AWS-specific section:** So sánh Infra Monitoring vs App Monitoring coverage cho experiment này.

| Layer | Metric/Alarm | Fired? | Expected? | Gap? |
|---|---|---|---|---|
| **Infra — CPU** | `*-cpu-high` | Yes/No | Yes/No | |
| **Infra — Memory** | `*-memory-high` | Yes/No | Yes/No | |
| **Infra — Task Count** | `*-running-task-low` | Yes/No | Yes/No | |
| **App — Error Rate** | `*-app-error-rate` | Yes/No | Yes/No | |
| **EventBridge — Deploy Failed** | `ecs-deployment-failed` | Yes/No | Yes/No | |
| **EventBridge — Task Stopped** | `ecs-task-stopped-abnormal` | Yes/No | Yes/No | |

> **Kết luận monitoring:** `<Infra alarms đủ/thiếu? App alarm bắt được? Blind spot nào phát hiện?>`

### Action Items (SMART)

> **SMART** = Specific, Measurable, Achievable, Relevant, Time-bound

| # | Category | Action | Owner | Deadline | Priority | Status |
|---|----------|--------|-------|----------|----------|--------|
| 1 | **[Fix]** | `<immediate fix>` | @... | YYYY-MM-DD | P1 | Open |
| 2 | **[Detect]** | `<improve monitoring/alarm>` | @... | YYYY-MM-DD | P1 | Open |
| 3 | **[Prevent]** | `<prevent recurrence — IaC, OPA, CI/CD>` | @... | YYYY-MM-DD | P2 | Open |
| 4 | **[Terraform]** | `<IaC improvement — drift detection, validation>` | @... | YYYY-MM-DD | P2 | Open |
| 5 | **[Runbook]** | `<update playbook/runbook>` | @... | YYYY-MM-DD | P2 | Open |

**Priority:**
- **P1:** Within 1 week — directly reduces MTTD/MTTR
- **P2:** Within 2 weeks — improves process/tooling
- **P3:** Within 1 month — nice-to-have

### Lessons Learned

> 1-3 bài học chính. Mỗi bài học phải **actionable** — không chỉ "we learned X" mà "next time, do Y".

1. **`<Bài học #1>`**
   - Production insight: `<how this applies to real production>`

2. **`<Bài học #2>`**
   - Production insight: `<how this applies to real production>`

3. **`<Bài học #3>`**
   - Production insight: `<how this applies to real production>`

### Metrics Summary

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **MTTD** (Detect) | `X phút` | ≤ 5 phút | ✅/❌ |
| **MTTA** (Acknowledge) | `X phút` | ≤ 5 phút | ✅/❌ |
| **MTTR** (Resolve) | `X phút` | ≤ 15 phút (drill) | ✅/❌ |
| **Prediction accuracy** | `X/Y` | ≥ 3/5 | ✅/❌ |
| **Alarms coverage** | `X/6 fired` | All expected fired | ✅/❌ |

---

## 📅 Follow-up Schedule

> Action items không có follow-up = không bao giờ complete.

- [ ] **24h:** Viết post-mortem (Section 2) dựa trên Incident Log (Section 1)
- [ ] **48h:** Review post-mortem — tự hỏi "có blame ai không? có systemic gap nào bỏ sót?"
- [ ] **1 week:** Check-in progress P1 action items
- [ ] **2 weeks:** Check-in progress P2 action items
- [ ] **Before next experiment:** Verify tất cả action items từ experiment trước đã completed

---

## 🔁 Blameless Principles (Nhắc nhở)

- ❌ "Tôi quên rollback IAM policy"
- ✅ "Rollback step không có automated verification — cần thêm `terraform plan` check"

- ❌ "Tôi không check alarm sớm"
- ✅ "Alarm routing chưa có auto-open dashboard khi fire"

- ❌ "Tôi deploy sai config"
- ✅ "CI/CD pipeline thiếu pre-deploy validation gate"

**Rule:** Mọi "human error" đều là **system gap**. Hệ thống tốt khiến human error khó xảy ra hoặc ít impact.

---

## 📎 Cross-references

- **Chaos Playbook:** [`AWS_CHAOS_PLAYBOOK.md`](./AWS_CHAOS_PLAYBOOK.md) — experiment details, inject/rollback commands
- **Architecture:** [`ARCHITECTURE.md`](../ARCHITECTURE.md) — infra topology, failure domains
- **Roadmap:** [`ROADMAP.md`](../ROADMAP.md) — phase context, where this experiment fits
- **On-premises post-mortems:** [`on-premises/post-mortems/`](../on-premises/post-mortems/) — reference format
- **On-premises golden example:** [`01-GOLDEN-EXAMPLE-DB-Saturation.md`](../on-premises/post-mortems/01-GOLDEN-EXAMPLE-DB-Saturation.md)
