# 🌪️ AWS Chaos Playbook

*Tài liệu thực hành Chaos Engineering dành riêng cho AWS Reliability Lab. Áp dụng phương pháp "Verify, don't trust".*

---

## � Cách đọc tài liệu này

Mỗi experiment đi theo cấu trúc 6 phase cố định:

| Phase | Mục đích | Câu hỏi cần trả lời |
|---|---|---|
| **0. Pre-flight** | Đảm bảo hệ thống KHỎE trước khi phá | "Steady state đã đạt chưa?" |
| **1. Baseline** | Chụp ảnh hiện trường | "Bằng chứng trạng thái trước inject là gì?" |
| **2. Inject Failure** | Gây án có chủ đích | "Tôi sẽ phá cái gì, ở đâu, trong bao lâu?" |
| **3. Observe & Triage** | Quan sát qua các Control Plane signals | "Hệ thống phản ứng thế nào? Alert có đến không?" |
| **4. Rollback & Recovery** | Khôi phục về steady state | "Recovery có tự động hay phải can thiệp?" |
| **5. Post-Mortem** | 5 Whys + Action Items | "Bài học hệ thống là gì? Guard rail nào cần build?" |

**Quy tắc cho người đọc:**
- Đọc HẾT 1 experiment trước khi gõ lệnh đầu tiên.
- Mở **3 terminals** song song khi vào Phase 3 (xem chi tiết từng exp).
- Ghi vào notebook cá nhân: `[HH:MM] event description` cho mỗi mốc thời gian quan trọng.
- Sau Phase 5: **đo Time-To-Detect (TTD)** = thời gian từ Inject đến lúc nhận alert đầu tiên trên Telegram.

---

## �🛡️ Nguyên tắc an toàn (The 3 Commandments)

1. **Always have a Stop Condition:** Mọi drill thủ công phải có Time-box (hẹn giờ) hoặc Script tự động Rollback.
2. **Start with the smallest Blast Radius:** Chỉ tác động lên 1 Task, 1 Rule, hoặc 1 AZ trước khi scale lên toàn hệ thống.
3. **Observe the Control Plane:** Khi App Logs bị ảnh hưởng, hãy nhìn vào ECS Events, CloudTrail và VPC Flow Logs.

---

## 🎯 Pod-based Chaos Philosophy (NEW STRATEGY)

Trong production, sự cố KHÔNG BAO GIỜ xảy ra ở 1 layer duy nhất. Một RDS failover sẽ kéo theo Connection Pool Exhaustion → Order Service Timeout → API Gateway 504 → User Retry Storm. 

Do đó, từ **POD 2** trở đi, chúng ta áp dụng 3 quy tắc mới cho mọi experiment:

### 1. Always inject at the infrastructure layer, observe at ALL layers
- **Inject:** RDS failover (AWS API)
- **Observe:** ECS task → App logs → Kafka consumer lag → Web UI error rate → Telegram alerts
- *Không chỉ nhìn 1 service, phải nhìn toàn bộ Data Flow.*

### 2. Measure the "User Pain Score"
- Không chỉ hỏi "Service có chết không?", mà phải hỏi "User có nhận thấy không?"
- **Metric cốt lõi:** `% successful orders` trong thời gian chaos.
- Nếu RDS failover 60s nhưng `User Pain Score = 0%` (nhờ retry logic + cache) → Drill THÀNH CÔNG.

### 3. Blast Radius = 1 Pod, không phải 1 Service
- Khi test RDS failover, **PHẢI** có Traffic Generator đang chạy (bắn real traffic).
- Khi test MSK broker loss, **PHẢI** có cả 2 Workers (Notification + Inventory) đang consume.
- *Chaos trên hệ thống đang "ngủ" là vô nghĩa.*

---

## 📡 Alerting Infrastructure (Iteration A — Đã triển khai)

Trước khi chạy bất kỳ experiment nào, **bạn cần hiểu rõ hệ thống alerting** đã được build sẵn — vì các experiment sẽ trigger nó.

### Pipeline alert hiện tại

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   ┌──────────────────┐         ┌──────────────────┐                     │
│   │ EventBridge Rule │         │ CloudWatch Alarm │                     │
│   │ (ECS events)     │         │ (Metrics)        │                     │
│   └────────┬─────────┘         └────────┬─────────┘                     │
│            │                            │                               │
│            └──────────────┬─────────────┘                               │
│                           ▼                                             │
│            ┌──────────────────────────┐                                 │
│            │  SNS Topics              │                                 │
│            │  • alerts-critical       │  ← outage / deployment fail     │
│            │  • alerts-warning        │  ← leading indicator / anomaly  │
│            └──────────────┬───────────┘                                 │
│                           ▼                                             │
│            ┌──────────────────────────┐                                 │
│            │  Lambda telegram-notifier│                                 │
│            │  (Python 3.12)           │                                 │
│            └──────────────┬───────────┘                                 │
└───────────────────────────┼─────────────────────────────────────────────┘
                            ▼
                  ┌──────────────────┐
                  │  Telegram chat   │
                  └──────────────────┘
```

### Catalog các nguồn alert đã wire sẵn

| Nguồn alert | Trigger | Topic | Bắt được experiment |
|---|---|---|---|
| EventBridge rule `ecs-deployment-failed` | ECS Deployment State Change `SERVICE_DEPLOYMENT_FAILED` | 🚨 critical | Exp 1, Exp 3A, Exp 3B (qua Circuit Breaker) |
| EventBridge rule `ecs-task-stopped-abnormal` | ECS Task State Change `stopCode ∈ {TaskFailedToStart, EssentialContainerExited}` | ⚠️ warning | Exp 3A (Birth), Exp 3B (OOM Runtime), Exp 4 (future) |
| CloudWatch alarm `memory-high` | `AWS/ECS MemoryUtilization > 85%` (2 min) | ⚠️ warning | Leading indicator — fire **trước** Exp 3B |
| CloudWatch alarm `cpu-high` | `AWS/ECS CPUUtilization > 80%` (5 min) | ⚠️ warning | Awareness — workload anomaly |
| CloudWatch alarm `running-task-low` | `ECS/ContainerInsights RunningTaskCount < 1` | 🚨 critical | Tổng quát — service down |

### One-time setup: Telegram Bot

> Chỉ cần làm **1 lần** khi deploy alerting infra lần đầu. Sau đó không cần lại.

1. Mở [@BotFather](https://t.me/BotFather) trên Telegram → `/newbot` → đặt tên → nhận **bot token** dạng `123456:ABC-DEF...`.
2. Tạo group/channel mới, add bot làm admin.
3. Send 1 tin nhắn bất kỳ vào group, rồi mở `https://api.telegram.org/bot<TOKEN>/getUpdates` để lấy **chat_id** (số âm dạng `-100xxxxxxx`).
4. Lưu vào Secrets Manager (KHÔNG commit git):
   ```bash
   aws secretsmanager create-secret \
     --name /obs/lab/alerting/telegram \
     --description "Telegram bot token + chat_id for chaos alerts" \
     --secret-string '{"bot_token":"<TOKEN>","chat_id":"<CHAT_ID>"}' \
     --region ap-southeast-2
   ```
5. Verify đọc được: `aws secretsmanager get-secret-value --secret-id /obs/lab/alerting/telegram --query SecretString --output text`

---

### Pre-flight: verify alerting healthy TRƯỚC mọi experiment

> Không bao giờ drill nếu alerting đang bệnh — bạn sẽ không phân biệt được "hệ thống không alert" vs "hệ thống không fail".

```bash
# 1. Lambda alive — invoke direct với dummy payload
aws lambda invoke \
  --function-name obs-lab-telegram-notifier \
  --payload '{"Records":[{"Sns":{"TopicArn":"arn:aws:sns:ap-southeast-2:730335245469:obs-lab-alerts-critical","Message":"{\"AlarmName\":\"preflight-check\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"manual preflight from drill\",\"Region\":\"ap-southeast-2\",\"AWSAccountId\":\"730335245469\"}"}}]}' \
  --cli-binary-format raw-in-base64-out /tmp/preflight.json
cat /tmp/preflight.json   # Kỳ vọng: {"status":"ok"}
# ✅ Bạn PHẢI nhận được tin nhắn Telegram trong < 5 giây.

# 2. 8 alarms ở state OK (4 per service: 3 infra + 1 app, không INSUFFICIENT_DATA)
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-payment-service-memory-high \
                obs-lab-payment-service-cpu-high \
                obs-lab-payment-service-running-task-low \
                obs-lab-payment-service-app-error-rate \
                obs-lab-order-service-memory-high \
                obs-lab-order-service-cpu-high \
                obs-lab-order-service-running-task-low \
                obs-lab-order-service-app-error-rate \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table

# 3. EventBridge rules ENABLED
aws events list-rules --name-prefix obs-lab-ecs- \
  --query 'Rules[*].{Name:Name,State:State}' --output table
```

Nếu bất kỳ check nào FAIL, **STOP** — sửa alerting trước, không drill.
---
### 🛡️ Pod Completeness Pre-flight (Bắt buộc từ POD 2)
Trước khi inject failure vào POD 2 hoặc POD 3, phải đảm bảo Pod đang "sống" hoàn chỉnh:

```bash
# 1. Verify Traffic Generator đang chạy (User Pain Score baseline)
curl -X POST http://<traffic-gen-ip>:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 600}'

# 2. Verify X-Ray Trace xuyên suốt Pod (User → API GW → Order → Payment → DB)
# (Check trên X-Ray Console: Service Map phải hiện đủ 6 nodes)

# 3. Verify Kafka Consumers không có Lag
aws cloudwatch get-metric-statistics \
  --namespace "AWS/Kafka" --metric-name "MaxOffsetLag" \
  --dimensions Name=Cluster Name,Value=<msk-cluster> \
  --start-time $(date -u -d '5 min ago' +%FT%TZ) --end-time $(date -u +%FT%TZ) \
  --period 300 --statistics Maximum
# Kỳ vọng: Maximum < 10
❌ Nếu Traffic Gen chưa chạy hoặc X-Ray trace bị cụt → STOP. Fix Pod trước khi drill.
---

# 🧪 Experiment 1: The IAM Blackhole (Task Execution Role)

**SEV-3** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~15 phút

### 📚 Học được gì sau experiment này

- Phân biệt sống còn giữa **Task Execution Role** (ECS Agent dùng để kéo image / ghi log) và **Task Role** (App code dùng để gọi AWS API).
- Hiểu cơ chế **`deployment_circuit_breaker`** trong ECS — nó cứu service khỏi outage NHƯNG che giấu root cause.
- Đọc và phân tích **ECS Events** — "black box recorder" duy nhất khi container chưa kịp khởi động.
- Hiểu khái niệm **Drift Detection** trong Terraform khi infra bị thay đổi ngoài IaC.
- **TTD target:** Telegram alert 🚨 `SERVICE_DEPLOYMENT_FAILED` phải đến trong **≤ 5 phút** sau khi force-deploy.

### ⚠️ Bẫy thường gặp (Common pitfalls)

- ❌ Nhìn `RunningCount: 1` → kết luận "hệ thống ổn" → BỎ LỠ deployment failed.
- ❌ Mở CloudWatch Logs để debug → tab trống → ngỡ Logs bị lỗi (thực ra container chưa bao giờ tồn tại).
- ❌ Gỡ luôn `AmazonECSTaskExecutionRolePolicy` mà không backup ARN trước → mất time rollback.

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

> *Mục tiêu: Đảm bảo hệ thống đang KHỎE trước khi phá. Không bao giờ drill trên một hệ thống đang ốm.*

Mở Terminal và chạy:

```bash
# 1. Check xem service có đang RUNNING không
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount, Events:events[0:2]}' \
    --output table
```

✅ **Kỳ vọng:** `Status: ACTIVE`, `Running: 1`, `Desired: 1`. Events gần nhất không có lỗi.  
❌ **Nếu sai:** DỪNG LẠI. Fix hệ thống trước khi drill.

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

> *Mục tiêu: Chụp ảnh "hiện trường" trước khi gây án.*

```bash
# 2. Lưu lại ARN của Task Execution Role hiện tại
EXEC_ROLE_ARN=$(aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].taskDefinition' --output text | xargs -I {} aws ecs describe-task-definition --task-definition {} --query 'taskDefinition.executionRoleArn' --output text)
echo "Current Exec Role: $EXEC_ROLE_ARN"

# 3. Lấy tên Log Group để tí nữa verify
LOG_GROUP="/ecs/<your-project>/payment-service"
echo "Log Group: $LOG_GROUP"
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Service RUNNING, Exec Role attached.

---

## 💥 Phase 2: Inject Failure (The Blackhole)

Chúng ta sẽ dùng AWS Console để inject (vì IAM Policy UI trực quan), nhưng sẽ dùng CLI để quan sát.

1. Mở AWS Console → IAM → Roles → Tìm role `<project_name>-ecs-task-execution`.
2. Tab **Permissions** → Tìm policy `AmazonECSTaskExecutionRolePolicy` (hoặc policy custom cho CloudWatch Logs/Secrets Manager).
3. Bấm **Remove** (Gỡ bỏ).
4. Quay lại Terminal, ép ECS spawn task mới:

```bash
aws ecs update-service \
    --cluster <your-cluster-name> \
    --service payment-service \
    --force-new-deployment
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Removed Execution Role policy + Force Deploy.

---

## 🔍 Phase 3: Observe & Triage (The Investigation)

> Đây là lúc bạn đeo kính lúp của SRE. KHÔNG MỞ AWS CONSOLE. Hãy nhìn Terminal.

### Bước 3.1: Đợi 1-2 phút, sau đó check Events

```bash
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].events[0:5]' \
    --output table
```

👁️ **The SRE Lens (Bạn sẽ thấy gì?):**

Bạn sẽ KHÔNG thấy task mới RUNNING. Thay vào đó, ECS Events sẽ liên tục bắn ra:

- `"service payment-service was unable to place a task... Reason: AccessDeniedException. You are not authorized to perform: logs:CreateLogStream..."`
- hoặc `"...ecr:GetAuthorizationToken..."`

### Bước 3.2: Check xem Service có tự phục hồi không? (Circuit Breaker in Action)

```bash
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount, Deployments:deployments[*].{Status:status, Running:runningCount, Rollout:rolloutState}}' \
    --output json
```

👁️ **Kết quả (Cú twist mà nhiều người không ngờ):**

Bạn sẽ thấy **2 deployments**:

```json
"Deployments": [
  { "Status": "PRIMARY",   "Running": 1, "Rollout": "COMPLETED" },
  { "Status": "INACTIVE",  "Running": 0, "Rollout": "FAILED" }
]
```

💡 **What just happened?**

1. `force-new-deployment` tạo ra deployment mới (task mới).
2. Task mới lặp đi lặp lại: `PROVISIONING` → `PENDING` → `STOPPED` (vì thiếu IAM policy).
3. Sau vài lần retry thất bại, **`deployment_circuit_breaker`** kích hoạt → đánh dấu deployment mới là `FAILED`.
4. Vì `rollback = true`, ECS tự động rollback về task definition cũ → **Task cũ vẫn sống**, `Running: 1`.

🚨 **THE "AHA!" MOMENT (Bẫy tinh vi hơn bạn tưởng):**

Service **KHÔNG chết trắng** nhờ Circuit Breaker. Nhưng đây chính là **"Silent Failure"** — nếu bạn chỉ nhìn `Running: 1` và vội kết luận "hệ thống ổn", bạn sẽ bỏ lỡ hoàn toàn thực tế rằng **deployment vừa thất bại và đã bị rollback**.

### Bước 3.3: Tìm bằng chứng trong ECS Events (The Forensics)

```bash
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].events[0:5].message' \
    --output table
```

👁️ **Bạn sẽ thấy chuỗi events như sau (đọc từ dưới lên):**

1. `"...was unable to place a task... AccessDeniedException..."` (Task mới fail)
2. `"...deployment ecs-svc/xxx circuit breaker: failure threshold exceeded..."` (Circuit Breaker trip)
3. `"...deployment ecs-svc/xxx rolled back..."` (Auto rollback)
4. `"...has reached a steady state."` (Service ổn định lại với task cũ)

💡 **Bài học quan trọng:**

- **Circuit Breaker bảo vệ Availability** (service không chết trắng), nhưng **che giấu Root Cause** nếu bạn không đọc Events.
- Trong Production, bạn CẦN CloudWatch Alarm trên ECS Event `SERVICE_DEPLOYMENT_FAILED` để team được alert ngay lập tức, thay vì phát hiện muộn rằng "code mới không lên được".
- Task cũ vẫn chạy = **App version cũ vẫn serve traffic**. Nếu đây là hotfix cho bug nghiêm trọng, hotfix đó sẽ KHÔNG được deploy mà bạn không hề biết.

### Bước 3.4: Kiểm tra CloudWatch Logs

```bash
# (Yêu cầu AWS CLI v2. Nếu dùng v1, hãy mở Console CloudWatch Logs để verify)
aws logs tail $LOG_GROUP --since 10m
```

👁️ **Kết quả:** Hoàn toàn trống trơn.

💡 **Bài học:** Nếu bạn chỉ dựa vào App Logs để debug, bạn sẽ bị "mù" (Blindspot). Bạn bắt buộc phải nhìn vào Control Plane Logs (ECS Events).

### Bước 3.5: Watch Telegram (Verify your guard rails)

> Đây là phần mới sau Iteration A. Mọi drill từ giờ phải verify alert thật sự đến.

**Mở Telegram chat** và đợi tin nhắn từ bot. Trong vòng 2-5 phút sau khi Circuit Breaker trip (Bước 3.2), bạn phải thấy:

```
🚨 CRITICAL: ECS Deployment State Change
Event:    SERVICE_DEPLOYMENT_FAILED
Cluster:  obs-cluster
Service:  service:payment-service
Rollout:  FAILED
Reason:   ECS deployment circuit breaker: tasks failed to start.
Source:   aws.ecs  |  Region: ap-southeast-2
```

**Ghi vào notebook:**
- `[HH:MM:SS]` Inject (force-new-deployment)
- `[HH:MM:SS]` Circuit breaker trip (Bước 3.2)
- `[HH:MM:SS]` 🚨 Telegram received  → **TTD = ?**

**Nếu KHÔNG nhận được Telegram trong 10 phút:**
```bash
# 1. Lambda có được invoke không?
aws logs tail /aws/lambda/obs-lab-telegram-notifier --since 15m --format short

# 2. EventBridge rule có match event không?
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events --metric-name MatchedEvents \
  --dimensions Name=RuleName,Value=obs-lab-ecs-deployment-failed \
  --start-time $(date -u -d '15 min ago' +%FT%TZ) --end-time $(date -u +%FT%TZ) \
  --period 60 --statistics Sum
```

### Bước 3.6 (Nâng cao): Terraform Drift Detection

Vì bạn vừa phá AWS bằng Console (ClickOps), Terraform sẽ phát hiện ra sự "trôi dạt" (Drift).

```bash
cd terraform/control-plane/lab
terraform plan | grep -A 5 "iam_role_policy_attachment"
```

👁️ **Kết quả:** Terraform sẽ báo `~ update in-place` hoặc `+ create` để attach lại policy.

💡 **Platform Mindset:** Trong Production, nếu ai đó lén gỡ policy này, Terraform Plan trong CI/CD pipeline sẽ "hét lên" và chặn không cho merge PR nếu không có sự chấp thuận.

---

## 🔄 Phase 4: Rollback & Recovery

> Circuit Breaker đã giữ service sống bằng task cũ. Nhưng IAM Policy vẫn đang bị drift — cần Terraform heal.

1. Đảm bảo code Terraform của bạn (`iam_ecs.tf`) vẫn còn nguyên vẹn policy attachment.
2. Chạy:

```bash
terraform apply -auto-approve
```

3. Quan sát Terminal: Terraform sẽ attach lại policy vào IAM Role.
4. Sau khi IAM được heal, force deploy lại để chứng minh task mới đã lên được:

```bash
aws ecs update-service \
    --cluster <your-cluster-name> \
    --service payment-service \
    --force-new-deployment

# Đợi 1-2 phút, sau đó verify
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Deployments:deployments[*].{Status:status, Rollout:rolloutState}}' \
    --output json
```

✅ **Kỳ vọng:** Chỉ còn 1 deployment duy nhất với `Rollout: COMPLETED`. Task mới đã chạy thành công.

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

Điền vào Incident Log của bạn.

| Câu hỏi | Trả lời của bạn (Gợi ý) |
|---------|------------------------|
| 1. Why did the deployment fail? | Task mới không thể chuyển sang trạng thái `RUNNING`. Circuit Breaker phát hiện và rollback. |
| 2. Why couldn't Task start? | ECS Agent bị chặn quyền `logs:CreateLogStream` (hoặc `ecr:GetAuthorizationToken`). |
| 3. Why was the permission blocked? | (Drill) Tôi đã cố tình gỡ IAM Policy khỏi Task Execution Role. |
| 4. Why didn't anyone notice immediately? | Circuit Breaker giữ task cũ sống → `Running: 1` → Dashboard vẫn xanh. Deployment thất bại nhưng **không ai bị alert**. |
| 5. Systemic Gap (Production)? | Nếu đây là hotfix cho critical bug, hotfix sẽ KHÔNG được deploy mà team không biết. Cần alert trên `SERVICE_DEPLOYMENT_FAILED`. |

**Action Items:**
1. ✅ **DONE (Iteration A.1.T4):** EventBridge Rule `ecs-deployment-failed` → SNS critical → Lambda Telegram. Xem [`control-plane/lab/observability.tf`](../control-plane/lab/observability.tf).
2. ⏸️ **Deferred (Sprint A.3):** OPA Rego policy chặn mọi PR Terraform cố tình xóa `AmazonECSTaskExecutionRolePolicy`. Sẽ implement khi có CI/CD.
3. 📝 **Backlog:** CloudWatch metric filter trên Lambda Logs `/aws/lambda/obs-lab-telegram-notifier` để alert khi bot tự nó chết (meta-alert).

---

# 🧪 Experiment 2: The Network Partition (Security Group Isolation)

**SEV-2** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~20 phút

### 📚 Học được gì sau experiment này

- Phân biệt sống còn giữa **Liveness** (container có chạy không) vs **Readiness** (network có thông không).
- Hiểu khái niệm **Zombie Task** — RUNNING + HEALTHY (theo Liveness) nhưng KHÔNG serve traffic.
- Đính chính hiểu lầm: **Circuit Breaker CHỈ hoạt động trong deployment**, không bảo vệ task đang chạy.
- Hiểu cơ chế Cloud Map health check (custom) vs ECS task health — 2 cấp độ độc lập.
- **TTD target:** Telegram alert ⚠️ Task Stopped phải đến trong **≤ 5 phút** (nếu ECS phát hiện task unhealthy).

### ⚠️ Bẫy thường gặp

- ❌ Kỳ vọng Circuit Breaker auto-rollback khi service bị cô lập → SAI. Circuit Breaker chỉ active trong deployment cycle.
- ❌ Khôi phục SG rule rồi vội test ngay → Cloud Map DNS cần ~10-30s để re-resolve IP mới (TTL = 10s trong cấu hình).
- ❌ Bỏ qua VPC Flow Logs — đây là evidence trail rõ ràng nhất chứng minh "gói tin bị REJECT ở SG layer".

### ⚠️ Quan trọng: Architecture Context

> `payment-service` hiện tại deploy với `enable_load_balancer = false` — chỉ dùng **Cloud Map** (service discovery DNS: `payment-service.ecommerce.local:5002`).
>
> Do đó experiment này **KHÔNG liên quan đến ALB Target Group**. Thay vào đó, ta sẽ cắt SG rule **App ↔ App** (service-to-service) để mô phỏng network partition giữa các microservices.

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

> *Mục tiêu: Đảm bảo payment-service đang reachable qua Cloud Map DNS.*

> 💡 **Lưu ý:** Image `python:3.12-slim-bookworm` không có `curl` hay `nslookup`.
> Tất cả lệnh trong container đều dùng **Python one-liners** (có sẵn trong image).

```bash
# 1. Lấy cluster và task info
CLUSTER=obs-cluster
SERVICE=payment-service
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE \
  --query 'taskArns[0]' --output text)
echo "Task: $TASK_ARN"

# 2. Verify task đang RUNNING
aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].{Status:lastStatus,Health:healthStatus,IP:containers[0].networkInterfaces[0].privateIpv4Address}' \
  --output table

# 3. Verify Cloud Map DNS resolve được
# (Chạy từ bên trong VPC — dùng ECS Exec)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive \
  --command "python -c \"import socket; print(socket.getaddrinfo('payment-service.ecommerce.local', 5002))\""
# Kỳ vọng: trả về private IP của task (trùng với IP ở bước 2)

# 4. Verify service endpoint
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive \
  --command "python -c \"import urllib.request; r=urllib.request.urlopen('http://localhost:5002/health/live'); print(r.status)\""
# Kỳ vọng: 200
```

✅ **Kỳ vọng:** Task RUNNING, DNS resolve thành công, health endpoint trả 200.

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

> *Mục tiêu: Chụp ảnh "hiện trường" Cloud Map và SG khi hệ thống khỏe mạnh.*

```bash
# Variables (điền đúng project/env của bạn)
PROJECT=obs
ENV=lab

# 1. Cloud Map: liệt kê instances đã đăng ký
SVC_DISCOVERY_ID=$(aws servicediscovery list-services \
  --query "Services[?Name=='payment-service'].Id" --output text)

aws servicediscovery list-instances --service-id $SVC_DISCOVERY_ID \
  --query 'Instances[*].{Id:Id,IP:Attributes.AWS_INSTANCE_IPV4}' --output table

# 2. SG: lấy App SG ID từ SSM (đã export sẵn bởi control-plane)
# Tên thực tế của SG là "obs-sg-app" — KHÔNG phải "*application*"
APP_SG_ID=$(aws ssm get-parameter \
  --name "/$PROJECT/$ENV/security/app_sg_id" \
  --query 'Parameter.Value' --output text)
echo "App SG: $APP_SG_ID"

# (Fallback nếu không có SSM — filter theo tag Name)
# APP_SG_ID=$(aws ec2 describe-security-groups \
#   --filters "Name=tag:Name,Values=$PROJECT-sg-app" \
#   --query 'SecurityGroups[0].GroupId' --output text)

aws ec2 describe-security-group-rules --filter "Name=group-id,Values=$APP_SG_ID" \
  --query 'SecurityGroupRules[?contains(Description, `Service-to-service`)].{RuleId:SecurityGroupRuleId,Direction:IsEgress,Ports:join(`-`,[to_string(FromPort),to_string(ToPort)]),Description:Description}' \
  --output table

# 3. Lưu SG Rule IDs để rollback nhanh
INGRESS_RULE_ID=$(aws ec2 describe-security-group-rules \
  --filter "Name=group-id,Values=$APP_SG_ID" \
  --query 'SecurityGroupRules[?contains(Description, `Service-to-service`) && IsEgress==`false`].SecurityGroupRuleId' \
  --output text)
EGRESS_RULE_ID=$(aws ec2 describe-security-group-rules \
  --filter "Name=group-id,Values=$APP_SG_ID" \
  --query 'SecurityGroupRules[?contains(Description, `Service-to-service`) && IsEgress==`true`].SecurityGroupRuleId' \
  --output text)
echo "Ingress Rule: $INGRESS_RULE_ID"
echo "Egress Rule:  $EGRESS_RULE_ID"
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Cloud Map instance registered, SG rules intact.

---

## 💥 Phase 2: Inject Failure (The Isolation)

Chúng ta sẽ dùng Terraform để gỡ bỏ SG rule **App ↔ App** — cắt đứt giao tiếp giữa các microservices.

1. Mở file `terraform/modules/security/security_groups.tf`.
2. Tìm 2 blocks:
   - `resource "aws_security_group_rule" "app_ingress_from_app"` (line ~121)
   - `resource "aws_security_group_rule" "app_egress_to_app"` (line ~131)
3. **Comment out CẢ HAI blocks**.
4. Chạy lệnh:

```bash
# Từ thư mục đang active (control-plane/lab hoặc data-plane)
cd terraform/control-plane/lab
terraform apply -auto-approve
```

> 💡 **Tại sao comment 2 rules thay vì 1?**
> Chỉ comment ingress thì egress vẫn cho phép gói tin đi ra — nhưng response không vào được (ingress blocked).
> Comment cả 2 cho clean: đảm bảo gói tin bị chặn CẢ 2 CHIỀU → VPC Flow Logs có REJECT entry rõ ràng.

📝 **Ghi vào notebook:** `[HH:MM:SS]` Inject: terraform apply gỡ `app_ingress_from_app` + `app_egress_to_app`.

---

## 🔍 Phase 3: Observe & Triage (The "Zombie" Investigation)

> Đây là lúc tư duy SRE của bạn được thử thách. HÃY MỞ 3 TERMINAL để thấy bức tranh toàn cảnh.

### Terminal 1: Giả lập Service-to-Service Call (The Symptom)

Dùng ECS Exec vào chính `payment-service` để self-test connectivity qua Cloud Map DNS:

```bash
# Dùng ECS Exec vào payment-service
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive --command "/bin/sh"

# Trong container shell — chạy vòng lặp Python:
python -c "
import urllib.request, urllib.error, time
while True:
    try:
        r = urllib.request.urlopen('http://payment-service.ecommerce.local:5002/health/live', timeout=3)
        print(r.status)
    except Exception as e:
        print(f'FAIL: {e}')
    time.sleep(2)
"
```

👁️ **The SRE Lens:**

- `urllib.request.urlopen('http://localhost:5002/health/live')` → vẫn trả **200** (vì localhost bypass SG).
- `urllib.request.urlopen('http://payment-service.ecommerce.local:5002/...')` → **timeout** hoặc **connection refused** (vì DNS resolve ra IP, nhưng SG chặn TCP connection ở port 5000-5005).

💡 **Tại sao?** Cloud Map DNS vẫn resolve đúng IP, nhưng VPC Security Group đã chặn gói tin TCP ở tầng network. DNS ≠ Connectivity.

### Terminal 2: Check Cloud Map Registration (The Control Plane)

```bash
# Cloud Map: instance vẫn registered?
aws servicediscovery list-instances --service-id $SVC_DISCOVERY_ID \
  --query 'Instances[*].{Id:Id,IP:Attributes.AWS_INSTANCE_IPV4}' --output table

# DNS resolve có trả IP? (dùng Python thay nslookup)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive \
  --command "python -c \"import socket; print(socket.getaddrinfo('payment-service.ecommerce.local', 5002))\""
```

👁️ **Kết quả (bẫy lớn):**

- Cloud Map instance vẫn `REGISTERED` ✅
- DNS vẫn resolve ra IP ✅

💡 **Cloud Map không có health check chủ động** (cấu hình hiện tại dùng `health_check_custom_config` với `failure_threshold = 1`, ECS tự quản lý registration). Cloud Map KHÔNG biết gói tin bị drop — nó chỉ biết "ECS task còn sống hay chết".

### Terminal 3: Check ECS Task Status (The Illusion / Bẫy lớn nhất)

```bash
aws ecs describe-services \
    --cluster $CLUSTER \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount, Deployments:deployments[*].{Status:status, Running:runningCount, Rollback:rolloutState}}' \
    --output json
```

👁️ **Kết quả (Cú sốc cho Junior SRE):**

- `Status: ACTIVE`
- `Running: 1`
- `Rollback: COMPLETED` (deployment cuối cùng đã thành công)

🚨 **THE "AHA!" MOMENT (Đính chính hiểu lầm tai hại):**

Nhiều người nghĩ rằng `deployment_circuit_breaker` sẽ tự động Rollback khi service bị network partition. **SAI!**

- Circuit Breaker CHỈ hoạt động trong quá trình **DEPLOYMENT** (khi Task mới đang cố gắng replace Task cũ).
- Nếu Task ĐANG CHẠY ỔN ĐỊNH mà bạn đột ngột cắt Network (SG Rule), ECS Control Plane KHÔNG giết Task đó, và KHÔNG Rollback.
- Dưới góc nhìn của ECS Agent: Container vẫn đang chạy (Liveness Probe = Pass, Process PID vẫn tồn tại). ECS không biết gì về việc AWS VPC Network đang drop gói tin.
- **Kết luận:** Bạn vừa tạo ra một **Zombie Task**. Nó vẫn tốn tiền CPU/RAM của bạn, vẫn ghi log "Server started on port 5002", nhưng không phục vụ bất kỳ microservice nào.

### Terminal 4 (Iteration A): Watch Telegram

Với Exp 2 (Cloud Map only, không ALB):

> ⚠️ **Alert sẽ KHÔNG đến** trong trường hợp này — đây là bài học quan trọng nhất.

Lý do: Không có ALB health check → không có deregistration → ECS không kill task → không có EventBridge `ecs-task-stopped-abnormal`. Payment-service trở thành **Zombie hoàn hảo** — invisible to all monitoring.

Đây chính là **Blind Spot** lớn nhất của kiến trúc Cloud Map-only:
- ALB-based services: ALB health check phát hiện → deregister → ECS kill → EventBridge fire ⚠️
- **Cloud Map-only services: KHÔNG có mechanism nào phát hiện network partition.**

📝 **Ghi vào notebook:**
- `[HH:MM:SS]` Inject (terraform apply gỡ SG rules)
- `[HH:MM:SS]` Terminal 1: connection timeout bắt đầu
- `[HH:MM:SS]` Terminal 2: Cloud Map vẫn registered (blind spot!)
- `[HH:MM:SS]` Terminal 3: ECS vẫn báo RUNNING (Zombie confirmed)
- `[HH:MM:SS]` Telegram: **KHÔNG có alert** → Blind Spot confirmed → Action Item

---

## 🔄 Phase 4: Rollback & Recovery

Khôi phục SG rules bằng Terraform.

1. Uncomment lại 2 blocks `app_ingress_from_app` + `app_egress_to_app` trong `security_groups.tf`.
2. Chạy:

```bash
terraform apply -auto-approve
```

3. Quan sát Terminal 1 (vòng lặp Python):
   - Đợi khoảng 10-30s (SG rule propagation + Cloud Map DNS TTL = 10s).
   - Output sẽ chuyển từ `FAIL: <urlopen error ...>` trở lại `200`.

4. Verify Cloud Map + Connectivity:

```bash
# Cloud Map vẫn registered (không thay đổi — nó chưa bao giờ deregister)
aws servicediscovery list-instances --service-id $SVC_DISCOVERY_ID --output table

# Connectivity restored
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive \
  --command "python -c \"import urllib.request; r=urllib.request.urlopen('http://payment-service.ecommerce.local:5002/health/live'); print(r.status)\""
# Kỳ vọng: 200
```

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời của bạn (Gợi ý) |
|---------|------------------------|
| 1. Why couldn't other services reach payment-service? | Security Group rule `app_ingress_from_app` (port 5000-5005, self-referencing) bị xóa. VPC network drop gói tin TCP. |
| 2. Why did Cloud Map still show the service as registered? | Cloud Map dùng `health_check_custom_config` — ECS quản lý registration dựa trên task lifecycle, không dựa trên network connectivity. Task vẫn RUNNING → vẫn registered. |
| 3. Why didn't ECS restart or rollback the task? | ECS chỉ kiểm tra Liveness (Container process có chạy không). Nó không kiểm tra Readiness (Network có thông không) với các task đã stable. Circuit Breaker chỉ active trong deployment cycle. |
| 4. Why is this more dangerous than ALB-based partition? | Với ALB, health check fail → ALB deregister → ECS eventually kill → EventBridge alert. Với Cloud Map-only, **không có mechanism nào phát hiện** → Zombie tồn tại vĩnh viễn cho đến khi người khác gọi vào và thấy timeout. |
| 5. Systemic Gap (Production)? | Cloud Map-only services CẦN health check bổ sung — hoặc app-level (liveness endpoint + health checker sidecar) hoặc infra-level (Route 53 health check on Cloud Map). |

**Action Items:**

1. 📝 **Backlog (Priority High):** Implement **synthetic health check** cho Cloud Map-only services. Options:
   - Route 53 Health Check trỏ vào Cloud Map service (cần private hosted zone + VPC resolver).
   - CloudWatch Synthetics canary: chạy định kỳ `curl payment-service.ecommerce.local:5002/health/live` từ Lambda trong VPC → alarm nếu fail.
   - App-level: mỗi service tự ping dependency và tự crash nếu không thông (self-preservation pattern).
2. 📝 **Backlog:** Self-preservation pattern — App tự crash nếu không nhận request nào trong 5 phút. Cần implement ở app code, không phải infra.
3. ✅ **DONE (Iteration A.1.T4):** EventBridge `ecs-task-stopped-abnormal` — bắt được failure **chỉ khi** có ALB hoặc khi container tự crash. KHÔNG bắt được Cloud Map Zombie.

---

# 🧪 Experiment 3: The Poison Config (Container Runtime Failure)

**SEV-3** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~20 phút

### 📚 Học được gì sau experiment này

- Làm chủ bảng **ExitCode signatures** — `null` / `137` / `1` — công cụ triage nhanh nhất trong Production.
- Hiểu 3 loại failure trong ECS Task lifecycle: **Birth**, **Runtime**, **Zombie**.
- Thấy `deployment_circuit_breaker` hoạt động ở cả 2 scénario (Bad Image và OOM) và phân biệt được qua diễn biến ECS Events.
- So sánh **leading vs lagging indicators**: Memory alarm (leading) fire TRƯỚC OOM, ExitCode 137 (lagging) chỉ fire SAU khi container chết.
- **TTD target:**
  - Scénario A (Bad Image): 🚨 critical trong **≤ 4 phút** (sau khi circuit breaker trip).
  - Scénario B (OOM): ⚠️ warning task-stopped mỗi 1-2 phút + 🚨 critical sau khi circuit breaker trip.

### ⚠️ Bẫy thường gặp

- ❌ Thấy `ExitCode null` và mở CloudWatch Logs tìm error → tab trống → ngỡ service đang chạy bình thường.
- ❌ Nhầm lẫn ExitCode 137 (OOM Kill) với ExitCode 139 (Segfault). 137 = 128 + 9 (SIGKILL).
- ❌ Quan sát chỉ 1 task STOPPED → bỏ lỡ pattern circuit breaker retry 2-3 lần trước khi rollback.

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

```bash
# Verify service đang khỏe
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount}' \
    --output table
```

✅ **Kỳ vọng:** `Running: 1`, `Desired: 1`.

---

## 📊 Phase 1: Baseline

```bash
# Lưu lại Task Definition revision hiện tại (sẽ cần so sánh sau)
CURRENT_TD=$(aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].taskDefinition' --output text)
echo "Current TD: $CURRENT_TD"

# Verify CloudWatch Logs đang ghi bình thường
LOG_GROUP="/ecs/<your-project>/payment-service"
aws logs tail $LOG_GROUP --since 5m --format short | tail -5
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Service RUNNING, Logs đang ghi bình thường.

---

## 💥 Phase 2: Inject Failure

### Scenario A: Image Tag Không Tồn Tại

Trong `data-plane/payment-service/terraform.tfvars`, đổi image tag thành giá trị không tồn tại:

```hcl
# terraform.tfvars
image_tag = "this-tag-does-not-exist-v999"
```

Chạy:

```bash
cd terraform/data-plane/payment-service
terraform apply -auto-approve
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Deployed non-existent image tag.

### Scenario B: Memory Starvation (OOM Kill)

Trong `data-plane/payment-service/terraform.tfvars`, giảm memory xuống mức không đủ cho app:

```hcl
# terraform.tfvars — giá trị gốc: memory = 512
memory = 256    # Flask + dependencies thường cần ~300-400MB
```

> ⚠️ Fargate chỉ chấp nhận một số tổ hợp CPU/Memory cố định. Với `cpu = 256`, memory hợp lệ là: 512, 1024, 2048.
> Nếu set `memory = 256` mà Terraform báo lỗi validation, hãy giữ `memory = 512` và thay đổi sang **Scenario A**.

Chạy:

```bash
cd terraform/data-plane
terraform apply -auto-approve
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Reduced memory to trigger OOM Kill.

---

## 🔍 Phase 3: Observe & Triage

> Mở 2 Terminal: 1 để theo dõi Events, 1 để check Logs.

### Bước 3.1: Theo dõi ECS Events (Circuit Breaker timeline)

```bash
# Chạy lặp mỗi 15s để thấy Circuit Breaker "trưởng thành"
while true; do
  echo "=== $(date) ==="
  aws ecs describe-services \
      --cluster <your-cluster-name> \
      --services payment-service \
      --query 'services[0].{Running:runningCount, Deployments:deployments[*].{Status:status, Running:runningCount, Rollout:rolloutState}, Events:events[0:3].message}' \
      --output json
  echo ""
  sleep 15
done
```

👁️ **The SRE Lens (Timeline bạn sẽ thấy):**

| Thời điểm | Event | Ý nghĩa |
|---|---|---|
| T+0s | `deployment started` | Terraform tạo Task Definition mới, ECS bắt đầu deploy |
| T+30-60s | `unable to pull image` (Scenario A) hoặc `OutOfMemoryError` (Scenario B) | Task mới chết |
| T+60-120s | Lặp lại 2-3 lần | ECS retry theo exponential backoff |
| T+120-180s | `circuit breaker: failure threshold exceeded` | Circuit Breaker trip! |
| T+180-240s | `deployment rolled back` + `steady state` | Auto-rollback về Task Definition cũ |

### Bước 3.2: So sánh tín hiệu Logs (Điểm khác biệt then chốt)

#### Scenario A (Bad Image Tag):

```bash
aws logs tail $LOG_GROUP --since 10m --format short | tail -5
```

👁️ **Kết quả:** **Hoàn toàn trống** — giống hệt Experiment 1 (IAM Blackhole).

💡 **Tại sao?** Image pull failure xảy ra TRƯỚC khi container khởi động. Không có process nào chạy → Không có log nào được ghi.

#### Scenario B (OOM Kill):

```bash
aws logs tail $LOG_GROUP --since 10m --format short | tail -10
```

👁️ **Kết quả:** Có **vài dòng log** trước khi chết:

```
[INFO] Starting gunicorn 21.2.0
[INFO] Listening at: http://0.0.0.0:5002
[INFO] Worker booting...
 ← Đột ngột cắt ngang, không có "Server started" hoặc "Ready"
```

💡 **Tại sao?** Container CHẠY ĐƯỢC (process start) nhưng bị Linux OOM Killer giết khi vượt memory limit. Log bị cắt ngang giữa chừng.

### Bước 3.3: Tìm STOPPED Tasks để phân biệt Root Cause

```bash
# Lấy task STOPPED gần nhất
STOPPED_TASK=$(aws ecs list-tasks \
    --cluster <your-cluster-name> \
    --service-name payment-service \
    --desired-status STOPPED \
    --query 'taskArns[0]' --output text)

# Xem chi tiết lý do chết
aws ecs describe-tasks \
    --cluster <your-cluster-name> \
    --tasks $STOPPED_TASK \
    --query 'tasks[0].{StoppedReason:stoppedReason, StopCode:stopCode, Containers:containers[0].{ExitCode:exitCode, Reason:reason, LastStatus:lastStatus}}' \
    --output json
```

👁️ **So sánh kết quả:**

| Field | Scenario A (Bad Image) | Scenario B (OOM Kill) |
|---|---|---|
| `StopCode` | `TaskFailedToStart` | `EssentialContainerExited` |
| `StoppedReason` | `CannotPullContainerError: ...` | `OutOfMemoryError: Container killed due to memory usage` |
| `ExitCode` | `null` (chưa bao giờ chạy) | `137` (SIGKILL = 128 + 9) |
| `Reason` | `CannotPullContainerError` | `OutOfMemoryError` |

🚨 **THE "AHA!" MOMENT:**

- **ExitCode `null`** = Container chưa bao giờ khởi động (Birth Failure — same as Experiment 1)
- **ExitCode `137`** = Container đã chạy nhưng bị SIGKILL (Runtime Failure — Linux OOM Killer)
- **ExitCode `1`** = App crash do exception (Runtime Failure — App bug)

Đây là 3 "chữ ký" (signatures) mà SRE phải thuộc lòng để triage nhanh trong Production:

```
ExitCode = null  → Check IAM / ECR / Image tag    (Control Plane issue)
ExitCode = 137   → Check memory limits / profiling  (Resource issue)
ExitCode = 1     → Check app logs / env vars         (Application issue)
```

### Bước 3.4: Verify Circuit Breaker đã rollback thành công

```bash
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Running:runningCount, TaskDef:taskDefinition, Deployments:deployments[*].{Status:status, Rollout:rolloutState}}' \
    --output json
```

👁️ **Kết quả:** `Running: 1`, `taskDefinition` trỏ về revision CŨ (so sánh với `$CURRENT_TD` đã lưu ở Phase 1).

### Bước 3.5: Watch Telegram (NEW — Iteration A)

Với Exp 3, bạn sẽ thấy **CHUỖI alert** chứ không phải 1 alert đơn lẻ — đây là pattern thực tế nhất trong Production:

**Scenario A (Bad Image):**
```
[T+60s]  ⚠️ ECS Task State Change
         stopCode: TaskFailedToStart
         reason:   CannotPullContainerError: ... not found: manifest unknown

[T+120s] ⚠️ ECS Task State Change (lần 2 — retry)
         stopCode: TaskFailedToStart

[T+180s] 🚨 ECS Deployment State Change
         eventType: SERVICE_DEPLOYMENT_FAILED
         reason:    ECS deployment circuit breaker: tasks failed to start.
```

**Scenario B (OOM Kill):**
```
[T+45s]  ⚠️ ECS Task State Change
         stopCode: EssentialContainerExited
         (exitCode 137 trong detail)

[T+90s]  ⚠️ ECS Task State Change (retry lần 2)

[T+150s] 🚨 ECS Deployment State Change → SERVICE_DEPLOYMENT_FAILED
```

**🎓 Bài học từ chuỗi alert:**
- Bạn nhìn thấy **circuit breaker retry pattern** rõ ràng — đếm số ⚠️ trước khi 🚨 fire.
- ⚠️ warning đến TRƯỚC 🚨 critical — đây là cảnh báo sớm. Trong Production, có thể auto-trigger rollback ngay khi nhận 2 ⚠️ liên tiếp thay vì đợi circuit breaker.

**Ghi vào notebook:**
- `[HH:MM:SS]` Inject (terraform apply bad config)
- `[HH:MM:SS]` ⚠️ Telegram task-stopped #1
- `[HH:MM:SS]` ⚠️ Telegram task-stopped #2
- `[HH:MM:SS]` 🚨 Telegram deployment-failed → **TTD = ?**
- Đếm: bao nhiêu ⚠️ trước khi 🚨? (so sánh với `deployment_circuit_breaker.failure_threshold` trong ecs-service module)

---

## 🔄 Phase 4: Rollback & Recovery

Khôi phục config gốc trong `data-plane/payment-service/terraform.tfvars`:

```hcl
# terraform.tfvars — khôi phục giá trị gốc
image_tag = "<your-working-tag>"   # e.g., "ecs-fargate-v1"
memory    = 512
```

```bash
cd terraform/data-plane/payment-service
terraform apply -auto-approve
```

Verify:

```bash
# Đợi 1-2 phút, sau đó check
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Running:runningCount, Deployments:deployments[*].{Status:status, Rollout:rolloutState}}' \
    --output json
```

✅ **Kỳ vọng:** 1 deployment duy nhất, `Rollout: COMPLETED`.

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Scenario A (Bad Image) | Scenario B (OOM Kill) |
|---------|----------------------|---------------------|
| 1. Why did deployment fail? | ECS không thể pull image từ ECR — tag không tồn tại. | Container bị Linux OOM Killer giết — vượt memory limit. |
| 2. Why was the wrong config deployed? | (Drill) Tôi cố tình đặt image tag sai. | (Drill) Tôi cố tình giảm memory xuống quá thấp. |
| 3. How did we detect it? | ECS Events + Circuit Breaker trip. CloudWatch Logs trống. | ECS Events + ExitCode `137`. CloudWatch Logs bị cắt ngang. |
| 4. Why didn't it cause outage? | Circuit Breaker rollback giữ task cũ sống. | Circuit Breaker rollback giữ task cũ sống. |
| 5. Systemic Gap (Production)? | CI/CD pipeline nên validate image tag tồn tại TRƯỚC khi deploy. | Cần load testing + memory profiling để set đúng resource limits. |

**Action Items:**

1. ⏸️ **Deferred (Sprint A.3):** CI/CD Gate — thêm bước `aws ecr describe-images --image-ids imageTag=$TAG` trong pipeline. Sẽ làm khi có CI/CD.
2. 📝 **Backlog:** Resource Baseline — chạy load test để xác định baseline memory, set Fargate memory = `baseline × 1.5`.
3. ✅ **DONE (Iteration A.2.T2):** CloudWatch Alarm `memory-high` trên `MemoryUtilization > 85%`. Xem [`control-plane/lab/observability.tf`](../control-plane/lab/observability.tf). Verify recurring bằng Experiment 3.5 dưới đây.
4. ✅ **DONE (Tài liệu hóa):** Diagnostic Cheat Sheet `null` / `137` / `1` — đã có trong Bước 3.3 của experiment này.

---

# 🧪 Experiment 3.5: Memory Pressure Drill (Leading Indicator Verify)

**SEV-4** | **Blast Radius:** 1 ECS Task (in-place, không tái deploy) | **Thời gian:** ~10 phút

> **Đây là drill kiểm tra "alarm còn work không"** — chạy định kỳ (tháng/quý) để đảm bảo `MemoryUtilization > 85%` alarm vẫn fire đúng, Telegram vẫn nhận tin, và team chưa quên cách diễn giải nó.
>
> Khác với Experiment 1-3 (full chaos, có 5 phase), drill này ngắn vì:
> - Inject KHÔNG phá deployment.
> - Recovery tự động khi `stress-ng --timeout` hết.
> - Mục tiêu duy nhất: verify **leading indicator** vs **lagging indicator**.

### 📚 Học được gì sau drill này

- Hiểu cách dùng **ECS Exec** để inject failure mà không cần thay đổi infra.
- Quan sát trực tiếp **leading indicator fire TRƯỚC lagging indicator** — bằng chứng sống cho lý thuyết.
- Đo độ trễ thực tế từ "metric breach threshold" → "alarm fire" → "Telegram received". Số liệu này dùng để tinh chỉnh `evaluation_periods` sau này.
- **TTD target:** ⚠️ Telegram alert `memory-high` đến trong **≤ 3 phút** sau khi bắt đầu stress.

### ⚠️ Bẫy thường gặp

- ❌ Set `--vm-bytes` quá cao (sát limit) → OOM Kill xảy ra TRƯỚC khi alarm fire → bạn đang test Experiment 3B, không phải leading indicator.
- ❌ Quên `--timeout` → stress chạy mãi → task bị OOM kill → đảo chiều thí nghiệm.
- ❌ Chạy stress 30 giây → alarm cần `evaluation_periods × period = 2 × 60s = 120s` sustained → không fire → tưởng alarm hỏng.

### Phase 0 — Pre-flight

```bash
# 1. Lấy memory limit thực tế của task (để chọn --vm-bytes an toàn)
CLUSTER=obs-cluster
SERVICE=payment-service
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].{Memory:memory,Containers:containers[*].{Name:name,Memory:memory}}' \
  --output table
# Ghi nhận giá trị Memory (vd: 512MB).
# --vm-bytes nên = 70% × Memory = ~360MB cho task 512MB.
# Đủ để vượt 85% (cộng với app baseline) nhưng KHÔNG đủ để trigger OOM Kill.

# 2. ECS Exec enabled?
aws ecs describe-services --cluster $CLUSTER --services $SERVICE \
  --query 'services[0].enableExecuteCommand'
# Kỳ vọng: true. Nếu false → sửa modules/compute/ecs-service/main.tf
# (set enable_execute_command = true) rồi terraform apply trước khi drill.

# 3. Alarm hiện đang OK?
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-payment-service-memory-high \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold}'
# Kỳ vọng: State = "OK". Nếu ALARM hoặc INSUFFICIENT_DATA → dừng, debug trước.
```

### Phase 1 — Inject Memory Pressure

```bash
# Mở 2 terminal:
# Terminal 1: exec vào container
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container payment-service --interactive --command "/bin/sh"

# --- TRONG container shell ---
# Cài stress-ng (apt cho Debian/Ubuntu, apk cho Alpine)
apt-get update -qq && apt-get install -y -qq stress-ng || \
  apk add --no-cache stress-ng

# Eat 360MB trong 3 phút (180s). Đủ thời gian để alarm fire (cần ≥2 phút sustained).
stress-ng --vm 1 --vm-bytes 360M --vm-keep --timeout 180s
# --vm-keep: giữ allocation, không free liên tục (mô phỏng memory leak).
```

📝 **Ghi vào notebook:** `[HH:MM:SS]` Inject memory stress 360MB × 180s.

### Phase 2 — Observe (Terminal 2, song song)

```bash
# Theo dõi metric real-time
watch -n 30 "aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=$CLUSTER Name=ServiceName,Value=$SERVICE \
  --start-time \$(date -u -d '5 min ago' +%FT%TZ) \
  --end-time \$(date -u +%FT%TZ) \
  --period 60 --statistics Average \
  --query 'Datapoints[*].{Time:Timestamp,Mem:Average}' --output table"

# Theo dõi state alarm
watch -n 30 "aws cloudwatch describe-alarms \
  --alarm-names obs-lab-payment-service-memory-high \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}' --output json"
```

👁️ **Timeline kỳ vọng:**

| T+ | Sự kiện | Verify ở đâu |
|---|---|---|
| 0s | Stress bắt đầu | Terminal 1 |
| ~60s | Memory metric đầu tiên > 85% xuất hiện | Terminal 2 metric |
| ~120s | `evaluation_periods = 2` đạt → alarm `OK → ALARM` | Terminal 2 state |
| ~125s | ⚠️ Telegram nhận `memory-high` ALARM | Telegram chat |
| ~180s | Stress kết thúc, memory về baseline | Terminal 1 logs |
| ~240s | Alarm `ALARM → OK` (cần 2 datapoint dưới threshold) | Terminal 2 state |
| ~245s | ⚠️ Telegram nhận `memory-high` OK (recovered) | Telegram chat |

### Phase 3 — Verify & Notebook

**Checklist sau drill:**

- [ ] Telegram nhận **2 tin nhắn**: 1 lúc `ALARM` + 1 lúc `OK`. Nếu thiếu tin OK → kiểm tra `ok_actions` trong `observability.tf`.
- [ ] **TTD ≤ 3 phút** (Inject → Telegram ALARM).
- [ ] **TTR ≤ 5 phút** (Stress end → Telegram OK).
- [ ] Task KHÔNG bị OOM Kill (chạy `aws ecs describe-tasks --tasks $TASK_ARN` confirm `lastStatus = RUNNING`, không có `stoppedAt`). Nếu task chết → giảm `--vm-bytes` lần sau.

**Ghi notebook:**
```
[HH:MM:SS] Drill start: --vm-bytes 360M
[HH:MM:SS] Memory > 85% lần đầu
[HH:MM:SS] Alarm → ALARM
[HH:MM:SS] ⚠️ Telegram ALARM received  → TTD = __s
[HH:MM:SS] Stress timeout
[HH:MM:SS] Alarm → OK
[HH:MM:SS] ⚠️ Telegram OK received     → TTR = __s
```

### Phase 4 — Tuning ý tưởng

Sau khi đo TTD nhiều lần, cân nhắc:

- TTD quá chậm (> 4 phút)? → Giảm `evaluation_periods` 2 → 1 (nhưng dễ false alarm với GC spike).
- TTD quá nhanh, false alarm? → Tăng `period` 60s → 300s.
- Memory baseline luôn > 60% → Investigate app: có memory leak? Có cần tăng task memory?

### Tần suất chạy drill

| Tình huống | Tần suất gợi ý |
|---|---|
| Sau mỗi `terraform apply` chạm `observability.tf` | 1 lần (smoke test) |
| Định kỳ hàng tháng | 1 lần (verify alerting infra) |
| Trước GameDay lớn | 1 lần (warm-up team) |
| Sau khi rotate Telegram bot token | 1 lần (verify Secrets Manager) |

---

# 🧪 Experiment 4: Task Role Blackhole (Runtime IAM)

**SEV-3** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~20 phút

### 📚 Học được gì sau experiment này

- Phân biệt **Task Execution Role** (ECS Agent dùng khi BIRTH — kéo image, ghi log, lấy secret) vs **Task Role** (App code dùng khi RUNTIME — gọi AWS SDK).
- Experiment 1 phá Execution Role → task **không bao giờ khởi động**. Experiment 4 phá Task Role → task **khởi động bình thường nhưng app bị lỗi khi gọi AWS API**.
- Hiểu tại sao đây là "The Silent Killer" — container RUNNING, health check PASS, nhưng **business logic chết**.
- Đây là failure mode phổ biến nhất trong production: **partial failure** mà monitoring cơ bản không bắt được.

### ⚠️ Bẫy thường gặp

- ❌ Task RUNNING + health check PASS → kết luận "mọi thứ ổn" → business logic fail silently.
- ❌ Nhầm lẫn Task Execution Role và Task Role → gỡ sai role → gây Birth failure thay vì Runtime failure.
- ❌ Không check app logs → không biết app đang trả 500 cho mọi request.

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

```bash
# 1. Payment service đang RUNNING
aws ecs describe-services \
    --cluster obs-cluster \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount}' \
    --output table

# 2. App đang respond bình thường (qua ECS Exec)
TASK_ARN=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name payment-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $TASK_ARN --container payment-service \
    --interactive --command \
    "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5002/health').read().decode())\""
```

✅ **Kỳ vọng:** `ACTIVE`, `Running: 1`, health check trả `200 OK`.

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 3. Lưu lại ARN của Task Role hiện tại
TASK_ROLE_ARN=$(aws ssm get-parameter \
    --name "/obs/lab/iam/task_role_arn" \
    --query 'Parameter.Value' --output text)
echo "Task Role: $TASK_ROLE_ARN"

# 4. List policies hiện tại trên Task Role
TASK_ROLE_NAME=$(echo $TASK_ROLE_ARN | awk -F'/' '{print $NF}')
aws iam list-attached-role-policies --role-name $TASK_ROLE_NAME \
    --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Service RUNNING, Task Role attached, app healthy.

---

## 💥 Phase 2: Inject Failure (The Silent Killer)

Gỡ bỏ policy Secrets Manager (hoặc S3/DynamoDB nếu app dùng) khỏi Task Role:

```bash
# 5. Gỡ policy truy cập Secrets Manager khỏi Task Role
# (Tìm policy ARN từ Bước 4 — thường là custom policy hoặc SecretsManagerReadWrite)
POLICY_ARN="<arn-from-step-4>"   # ← Thay bằng ARN policy thực tế

aws iam detach-role-policy \
    --role-name $TASK_ROLE_NAME \
    --policy-arn $POLICY_ARN

# 6. Force redeploy (Task mới sẽ dùng role đã bị gỡ policy)
aws ecs update-service --cluster obs-cluster \
    --service payment-service --force-new-deployment
```

> ⚠️ **Khác Exp 1:** Task sẽ khởi động THÀNH CÔNG (vì Execution Role vẫn nguyên). Chỉ khi app code gọi AWS API (ví dụ: Secrets Manager) thì mới fail.

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Removed Secrets Manager policy from Task Role + Force Deploy.

---

## 🔍 Phase 3: Observe & Triage (The Investigation)

### Bước 3.1: Check ECS — task mới có RUNNING không?

```bash
aws ecs describe-services --cluster obs-cluster \
    --services payment-service \
    --query 'services[0].{Running:runningCount, Deployments:deployments[*].{Status:status, Rollout:rolloutState}}' \
    --output json
```

👁️ **Cú twist:**

```json
{ "Running": 1, "Deployments": [{"Status": "PRIMARY", "Rollout": "COMPLETED"}] }
```

Task mới **RUNNING thành công**! Deployment **COMPLETED**! Mọi thứ trông "xanh lè".

### Bước 3.2: Nhưng app thực sự hoạt động thế nào?

```bash
# Gọi health check — vẫn OK (vì /health không gọi AWS API)
aws ecs execute-command --cluster obs-cluster \
    --task $(aws ecs list-tasks --cluster obs-cluster \
        --service-name payment-service --query 'taskArns[0]' --output text) \
    --container payment-service --interactive --command \
    "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5002/health').read().decode())\""

# Gọi business endpoint — FAIL!
aws ecs execute-command --cluster obs-cluster \
    --task $(aws ecs list-tasks --cluster obs-cluster \
        --service-name payment-service --query 'taskArns[0]' --output text) \
    --container payment-service --interactive --command \
    "python -c \"
import urllib.request, json
req = urllib.request.Request('http://localhost:5002/charge',
    data=json.dumps({'order_id':'test-iam','amount':10}).encode(),
    headers={'Content-Type':'application/json'}, method='POST')
try:
    resp = urllib.request.urlopen(req, timeout=10)
    print(resp.read().decode())
except Exception as e:
    print(f'ERROR: {e}')
\""
```

👁️ **Kết quả:** Health check trả 200 OK nhưng `/charge` trả 500 hoặc exception liên quan `AccessDeniedException`.

### Bước 3.3: Check CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
    --alarm-names obs-lab-payment-service-memory-high \
                  obs-lab-payment-service-cpu-high \
                  obs-lab-payment-service-running-task-low \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table
```

👁️ **Kết quả:** Tất cả alarms đều ở `OK`. **Không có alarm nào fire!**

🚨 **THE "AHA!" MOMENT:**

Đây là "The Silent Killer":
- `running-task-low`: OK — task đang RUNNING
- `memory-high`: OK — app không dùng nhiều memory
- `cpu-high`: OK — request đang fail nhanh, CPU thấp
- EventBridge: KHÔNG fire — deployment COMPLETED, task không STOPPED

**Kết luận:** Monitoring hiện tại **KHÔNG bắt được Runtime IAM failure**. Cần thêm application-level monitoring (HTTP error rate, 5xx count) — đây sẽ là action item cho iteration tiếp theo.

### Bước 3.4: Check App Logs (bằng chứng duy nhất)

```bash
LOG_GROUP="/ecs/obs/payment-service"
aws logs tail $LOG_GROUP --since 5m --format short 2>/dev/null | grep -i "error\|denied\|exception" | head -20
```

👁️ Đây là nơi DUY NHẤT bạn thấy lỗi — app logs ghi `AccessDeniedException`.

### Bước 3.5: Watch Telegram

👁️ **Kết quả:** Không có Telegram alert nào.

📝 **Ghi vào notebook:** `[HH:MM]` ❌ No Telegram alert — Silent Failure confirmed.

---

## 🔄 Phase 4: Rollback & Recovery

```bash
# 7. Attach lại policy
aws iam attach-role-policy \
    --role-name $TASK_ROLE_NAME \
    --policy-arn $POLICY_ARN

# 8. Force redeploy để task mới pick up
aws ecs update-service --cluster obs-cluster \
    --service payment-service --force-new-deployment

# 9. Đợi 2 phút, verify
aws ecs execute-command --cluster obs-cluster \
    --task $(aws ecs list-tasks --cluster obs-cluster \
        --service-name payment-service --query 'taskArns[0]' --output text) \
    --container payment-service --interactive --command \
    "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5002/health').read().decode())\""
```

✅ Kỳ vọng: App trả lại 200 OK cho cả `/health` và `/charge`.

Hoặc dùng Terraform heal:

```bash
cd terraform/control-plane/lab
terraform apply -auto-approve
```

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---|---|
| 1. Tại sao business logic fail? | App gọi Secrets Manager bị `AccessDeniedException`. |
| 2. Tại sao không có alarm? | Monitoring chỉ check infra metrics (CPU/Memory/TaskCount) — không check app-level errors. |
| 3. Tại sao health check vẫn PASS? | `/health` chỉ trả static response, không gọi AWS API. |
| 4. So sánh với Exp 1? | Exp 1 (Execution Role) → Birth failure → Circuit Breaker → Alert. Exp 4 (Task Role) → Runtime failure → **Silent**. |
| 5. Systemic Gap? | Cần **application-level alarm**: HTTP 5xx rate, error log metric filter, hoặc custom CloudWatch metric từ OTel. |

**Action Items:**
1. 📝 **Backlog:** CloudWatch Metric Filter trên app logs → đếm `ERROR` → alarm khi rate > threshold.
2. 📝 **Backlog:** OTel → CloudWatch custom metric `http.server.request.duration` với dimension `http.status_code=5xx`.
3. 📝 **Backlog:** Synthetic health check endpoint `/ready` gọi thật vào DB/Secrets Manager thay vì trả static.

---

# 🧪 Experiment 4B: Order-Service Poison Config (Alarm Verification)

**SEV-3** | **Blast Radius:** 1 ECS Service (`order-service`) | **Thời gian:** ~15 phút

### 📚 Học được gì sau experiment này

- **Verify** rằng CloudWatch Alarms `for_each` mới tạo thực sự fire cho `order-service`.
- Chứng minh **blast radius isolation**: lỗi order-service KHÔNG ảnh hưởng payment-service (CP/DP split + per-service state).
- So sánh **TTD** giữa 2 services — alarm config giống nhau → TTD nên tương đương.
- Lặp lại Experiment 3 nhưng target khác → **build muscle memory** cho incident response.

### ⚠️ Bẫy thường gặp

- ❌ Quên `terraform apply` ở `control-plane/` sau khi thêm `for_each` → alarms cho order-service chưa tồn tại.
- ❌ Nhầm folder: chạy terraform ở `data-plane/payment-service/` thay vì `data-plane/order-service/`.

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

```bash
# 1. Cả 2 services đang RUNNING
for svc in payment-service order-service; do
  echo "=== $svc ==="
  aws ecs describe-services --cluster obs-cluster --services $svc \
    --query 'services[0].{Status:status, Running:runningCount}' --output table
done

# 2. Alarms cho order-service ĐÃ TỒN TẠI (verify Issue 1 fix)
aws cloudwatch describe-alarms \
    --alarm-names obs-lab-order-service-memory-high \
                  obs-lab-order-service-cpu-high \
                  obs-lab-order-service-running-task-low \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table
```

✅ **Kỳ vọng:** Cả 3 alarms cho order-service phải tồn tại và ở state `OK` (hoặc `INSUFFICIENT_DATA` nếu vừa tạo).

> ⚠️ **STOP nếu alarms không tồn tại!** Chạy `cd terraform/control-plane/lab && terraform apply` trước.

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 3. Ghi nhận order-service task đang chạy
aws ecs list-tasks --cluster obs-cluster --service-name order-service \
    --query 'taskArns[0]' --output text

# 4. Verify payment-service cũng đang healthy (để so sánh sau)
aws ecs list-tasks --cluster obs-cluster --service-name payment-service \
    --query 'taskArns[0]' --output text
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Cả 2 services RUNNING. Alarms đã tạo.

---

## 💥 Phase 2: Inject Failure

Trong `data-plane/order-service/terraform.tfvars`, đổi image tag thành giá trị không tồn tại:

```hcl
# data-plane/order-service/terraform.tfvars
image_tag = "this-tag-does-not-exist-v999"
```

```bash
cd terraform/data-plane/order-service
terraform apply -auto-approve
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Deployed non-existent image tag to order-service.

---

## 🔍 Phase 3: Observe & Triage (The Investigation)

### Bước 3.1: Mở 3 Terminals song song

**Terminal 1 — Watch ECS Events (order-service)**
```bash
watch -n 10 "aws ecs describe-services --cluster obs-cluster \
    --services order-service \
    --query 'services[0].events[0:3].message' --output text"
```

**Terminal 2 — Watch Alarms (order-service)**
```bash
watch -n 15 "aws cloudwatch describe-alarms \
    --alarm-names obs-lab-order-service-running-task-low \
    --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}' --output table"
```

**Terminal 3 — Watch payment-service (blast radius check)**
```bash
watch -n 15 "aws ecs describe-services --cluster obs-cluster \
    --services payment-service \
    --query 'services[0].{Running:runningCount, Status:status}' --output table"
```

### Bước 3.2: Đợi 3-5 phút, quan sát

👁️ **Terminal 1** sẽ hiển thị chuỗi events:
1. `"unable to place a task... CannotPullContainerError..."` (image không tồn tại)
2. `"circuit breaker: failure threshold exceeded..."`
3. `"deployment rolled back..."`

👁️ **Terminal 2** sẽ chuyển sang `ALARM`:
```
State: ALARM
Reason: Threshold Crossed: 2 out of 2 datapoints were less than 1.0
```

👁️ **Terminal 3** — payment-service vẫn `Running: 1` — **blast radius isolated!** ✅

### Bước 3.3: Watch Telegram

Kỳ vọng nhận **2 alerts**:
1. 🚨 `SERVICE_DEPLOYMENT_FAILED` (EventBridge → critical) — deployment rolled back
2. 🚨 `running-task-low` (CloudWatch Alarm → critical) — RunningTaskCount < 1

📝 **Ghi vào notebook:**
- `[HH:MM:SS]` Inject (terraform apply)
- `[HH:MM:SS]` 🚨 Telegram: deployment-failed → **TTD₁ = ?**
- `[HH:MM:SS]` 🚨 Telegram: running-task-low → **TTD₂ = ?**
- So sánh với payment-service TTD từ Experiment 3.

---

## 🔄 Phase 4: Rollback & Recovery

Khôi phục image tag trong `data-plane/order-service/terraform.tfvars`:

```hcl
# terraform.tfvars — khôi phục giá trị gốc
image_tag = "ecs-fargate-v1"
```

```bash
cd terraform/data-plane/order-service
terraform apply -auto-approve
```

Đợi 2-3 phút, verify:
```bash
aws ecs describe-services --cluster obs-cluster --services order-service \
    --query 'services[0].{Running:runningCount, Deployments:deployments[*].{Status:status,Rollout:rolloutState}}' \
    --output json
```

✅ **Kỳ vọng:** `Running: 1`, 1 deployment với `Rollout: COMPLETED`.

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---|---|
| 1. Alarms `for_each` hoạt động? | ✅ / ❌ (ghi kết quả thực tế) |
| 2. TTD order-service vs payment-service? | Order TTD = ___s, Payment TTD = ___s (từ Exp 3) |
| 3. Blast radius isolated? | ✅ payment-service không bị ảnh hưởng |
| 4. Có alert nào KHÔNG fire? | Ghi lại nếu có |

**Action Items:**
1. 📝 So sánh TTD → nếu chênh lệch lớn, investigate pipeline delay.
2. ✅ Confirm alarms `for_each` pattern hoạt động → mẫu cho onboard services tiếp theo.

---

# 🧪 Experiment 5: Cascading Failure (Payment Slow → Order Timeout)

**SEV-2** | **Blast Radius:** 2 ECS Services (`payment-service` + `order-service`) | **Thời gian:** ~30 phút

> **Đây là experiment giá trị nhất** — lần đầu tiên test service-to-service failure chain. Mọi microservice architecture production đều gặp vấn đề này.

### 📚 Học được gì sau experiment này

- Hiểu **cascading failure pattern**: Payment chậm → Order timeout → User nhận lỗi, nhưng **không service nào "chết"**.
- Phân biệt **Timeout** vs **ConnectionError** — app xử lý khác nhau không? (Spoiler: hiện tại order-service catch generic `Exception`).
- Hiểu vì sao **retry without backoff** = "retry storm" = amplify failure.
- Đánh giá timeout config hiện tại: `timeout=5s` trong order-service vs `SLOW_RATE delay=3-6s` trong payment → **overlap zone** gây intermittent failure.
- Nhận ra monitoring hiện tại **KHÔNG bắt được** cascading failure (cả 2 tasks vẫn RUNNING, CPU/Memory bình thường).

### ⚠️ Bẫy thường gặp

- ❌ Cả 2 service RUNNING → dashboard xanh → "mọi thứ ổn" → user đang nhận 504 mà team không biết.
- ❌ Nhầm `PAYMENT_SLOW_RATE` (app env var) với `SLOW_RATE` (code variable name).
- ❌ Quên rollback `PAYMENT_SLOW_RATE` → payment chậm vĩnh viễn.

### 🧬 Kiến trúc dependency

```
User ──▶ Order Service (port 5001) ──POST /charge──▶ Payment Service (port 5002)
                   │                    timeout=5s              │
                   │                    no retry                │ PAYMENT_SLOW_RATE=1.0
                   │                                            │ → delay 3-6s mỗi request
                   ▼                                            ▼
          "payment_error"                              504 Gateway Timeout
          (catch Exception)                            (khi delay > 5s)
```

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

```bash
# 1. Cả 2 services RUNNING
for svc in payment-service order-service; do
  echo "=== $svc ==="
  aws ecs describe-services --cluster obs-cluster --services $svc \
    --query 'services[0].{Status:status, Running:runningCount}' --output table
done

# 2. Verify order → payment communication đang hoạt động
# (gọi order-service /health endpoint)
ORDER_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name order-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $ORDER_TASK --container order-service \
    --interactive --command \
    "python -c \"
import urllib.request
resp = urllib.request.urlopen('http://localhost:5001/health/live')
print('Order health:', resp.read().decode())
\""

# 3. Check PAYMENT_SLOW_RATE hiện tại (nên là 0.20 = 20% default)
PAYMENT_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name payment-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $PAYMENT_TASK --container payment-service \
    --interactive --command \
    "python -c \"import os; print('PAYMENT_SLOW_RATE:', os.environ.get('PAYMENT_SLOW_RATE', '0.20 (default)'))\""
```

✅ **Kỳ vọng:** Cả 2 RUNNING, communication OK, SLOW_RATE = 0.20 (default).

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 4. Gửi 5 request tới order-service /process, ghi nhận response time và kết quả
# ⚠️ Dùng integer product_id (1-5), KHÔNG dùng string (DB column products.id là INTEGER)
for i in $(seq 1 5); do
  echo "--- Request $i ---"
  aws ecs execute-command --cluster obs-cluster \
      --task $ORDER_TASK --container order-service \
      --interactive --command \
      "python -c \"
import urllib.request, json, time
start = time.time()
try:
    data = json.dumps({'product_id': $i, 'quantity': 1}).encode()
    req = urllib.request.Request('http://localhost:5001/process',
        data=data, headers={'Content-Type': 'application/json'}, method='POST')
    resp = urllib.request.urlopen(req, timeout=15)
    elapsed = time.time() - start
    body = json.loads(resp.read().decode())
    payment_status = body.get('payment', {}).get('status', 'unknown')
    print(f'Status: {resp.status}, Time: {elapsed:.2f}s, Payment: {payment_status}')
except urllib.error.HTTPError as e:
    elapsed = time.time() - start
    print(f'HTTP {e.code} after {elapsed:.2f}s')
    print(e.read().decode())
\""
  sleep 2
done
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: x/5 requests OK, avg response time = ___s.

> **Lưu ý Phase 1 (AWS):** `ENABLE_REDIS=false`, `ENABLE_KAFKA=false` → idempotency/cache/events disabled.
> Default `SLOW_RATE=0.20` → ~20% payment requests chậm 3-6s → một số request sẽ timeout (expected).

---

## 💥 Phase 2: Inject Failure

Inject `PAYMENT_SLOW_RATE=1.0` (100% requests chậm 3-6s) vào payment-service **qua Terraform**.

Trong `data-plane/payment-service/main.tf`, thêm env var vào block `environment`:

```hcl
  # Environment Variables
  environment = {
    SERVICE_NAME                  = var.service_name
    PORT                          = tostring(var.container_port)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    # Phase 1: Redis not deployed yet → disable idempotency
    ENABLE_REDIS                  = "false"
    PAYMENT_SLOW_RATE             = "1.0"     # ← INJECT: 100% requests slow 3-6s
  }
```

```bash
cd terraform/data-plane/payment-service
terraform apply -auto-approve
```

> ⚠️ **Đây KHÔNG phải lỗi infra** — service vẫn RUNNING, health check vẫn PASS. Chỉ có business endpoint bị chậm.

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: PAYMENT_SLOW_RATE=1.0 deployed to payment-service.

---

## 🔍 Phase 3: Observe & Triage (The Investigation)

### Bước 3.1: Đợi deployment payment hoàn tất (~2-3 phút)

```bash
watch -n 10 "aws ecs describe-services --cluster obs-cluster \
    --services payment-service \
    --query 'services[0].{Running:runningCount, Deployments:deployments[*].{Status:status,Rollout:rolloutState}}' \
    --output json"
```

Đợi đến khi `Rollout: COMPLETED`. Bấm `Ctrl+C` để thoát watch.

### Bước 3.2: Gửi request tới order-service (trigger cascading failure)

```bash
# Gọi từ TRONG order-service container
# ⚠️ Phải dùng integer product_id (1-5) — DB column products.id là INTEGER
ORDER_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name order-service --query 'taskArns[0]' --output text)

for i in $(seq 1 5); do
  echo "--- Request $i ---"
  aws ecs execute-command --cluster obs-cluster \
      --task $ORDER_TASK --container order-service \
      --interactive --command \
      "python -c \"
import urllib.request, json, time
start = time.time()
try:
    data = json.dumps({'product_id': $i, 'quantity': 1}).encode()
    req = urllib.request.Request('http://localhost:5001/process',
        data=data, headers={'Content-Type': 'application/json'}, method='POST')
    resp = urllib.request.urlopen(req, timeout=15)
    elapsed = time.time() - start
    body = json.loads(resp.read().decode())
    payment_status = body.get('payment', {}).get('status', 'unknown')
    print(f'Status: {resp.status}, Time: {elapsed:.2f}s, Payment: {payment_status}')
except urllib.error.HTTPError as e:
    elapsed = time.time() - start
    print(f'HTTP {e.code} after {elapsed:.2f}s')
    print(e.read().decode())
\""
  sleep 2
done
```

👁️ **Kết quả kỳ vọng (chuỗi cascading — PAYMENT_SLOW_RATE=1.0):**

| Request | HTTP Code | Payment status | Response time | Giải thích |
|---|---|---|---|---|
| 1 | 502 | `payment_error` | ~5s | Payment delay 3-6s, order timeout=5s → **timeout** |
| 2 | 200 | `success` | ~4s | Payment delay < 5s → vừa kịp (may mắn) |
| 3 | 502 | `payment_error` | ~5s | Payment delay > 5s → order timeout |
| ... | Intermittent | Intermittent | 4-6s | **Unpredictable** — đây chính là vấn đề |

> **Lưu ý:** HTTP 502 = `payment_error` được map bởi `map_order_status_to_http()` trong order-service.
> Order vẫn được tạo trong DB (status=`payment_error`), chỉ payment bị fail.

💡 **THE "AHA!" MOMENTS:**

1. **Overlap Zone**: `SLOW_RATE delay=3-6s` vs `order timeout=5s` → ~50% requests timeout, ~50% pass. Đây là **intermittent failure** — loại khó debug nhất.
2. **No retry**: Order-service không retry → 1 timeout = 1 lost payment.
3. **Silent degradation**: Cả 2 tasks RUNNING, CPU/Memory bình thường, **KHÔNG alarm nào fire**.

### Bước 3.3: Check CloudWatch Alarms

```bash
# Kiểm tra TẤT CẢ alarms
aws cloudwatch describe-alarms \
    --alarm-names obs-lab-payment-service-memory-high \
                  obs-lab-payment-service-cpu-high \
                  obs-lab-payment-service-running-task-low \
                  obs-lab-order-service-memory-high \
                  obs-lab-order-service-cpu-high \
                  obs-lab-order-service-running-task-low \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table
```

👁️ **Tất cả alarms: OK.** Monitoring hiện tại **hoàn toàn MÙ** trước cascading failure.

### Bước 3.4: Check App Logs (bằng chứng duy nhất)

```bash
# Order-service logs — sẽ thấy timeout errors
aws logs tail /ecs/obs/order-service --since 5m --format short 2>/dev/null \
    | grep -i "timeout\|error\|payment" | head -10

# Payment-service logs — sẽ thấy slow requests
aws logs tail /ecs/obs/payment-service --since 5m --format short 2>/dev/null \
    | grep -i "slow\|delay" | head -10
```

### Bước 3.5: Watch Telegram

👁️ **Kết quả:** Không có Telegram alert nào.

🚨 **CRITICAL LEARNING:** Cascading failure xảy ra ở **application layer**, trong khi monitoring hiện tại chỉ cover **infrastructure layer**. Đây là gap lớn nhất trong hệ thống observability hiện tại.

---

## 🔄 Phase 4: Rollback & Recovery

Xóa `PAYMENT_SLOW_RATE` khỏi `data-plane/payment-service/main.tf`:

```hcl
  # Environment Variables — khôi phục gốc (XÓA PAYMENT_SLOW_RATE, giữ ENABLE_REDIS)
  environment = {
    SERVICE_NAME                  = var.service_name
    PORT                          = tostring(var.container_port)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    # Phase 1: Redis not deployed yet → disable idempotency
    ENABLE_REDIS                  = "false"
    # PAYMENT_SLOW_RATE đã XÓA — app sẽ dùng default 0.20
  }
```

```bash
cd terraform/data-plane/payment-service
terraform apply -auto-approve
```

Đợi deployment hoàn tất (~2-3 phút), verify lại 5 requests:

```bash
ORDER_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name order-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $ORDER_TASK --container order-service \
    --interactive --command \
    "python -c \"
import urllib.request
resp = urllib.request.urlopen('http://localhost:5001/health/live')
print('Order health:', resp.read().decode())
\""
```

✅ **Kỳ vọng:** Response time trở lại bình thường.

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---|---|
| 1. Tại sao order trả payment_error? | Payment delay > order timeout (5s) → `ReadTimeout` → catch Exception → `payment_error`. |
| 2. Tại sao chỉ ~50% request fail? | Payment delay random 3-6s, overlap với timeout 5s → intermittent. |
| 3. Tại sao không có alarm? | Monitoring chỉ check infra (CPU/Memory/TaskCount), không check HTTP error rate. |
| 4. Timeout 5s có hợp lý? | Payment P99 latency = 6s → timeout < P99 = **guaranteed failure**. Cần tăng hoặc thêm retry. |
| 5. Systemic Gap? | Cần **HTTP error rate alarm** + **latency percentile alarm** (P95/P99). |

**Action Items:**
1. 📝 **Critical:** Thêm application-level metrics: HTTP 5xx rate, P95 latency (từ OTel → CloudWatch).
2. 📝 **Important:** Review timeout budget: `order timeout` > `payment P99 latency` + safety margin.
3. 📝 **Backlog:** Implement retry with exponential backoff trong order-service (nhưng cần idempotency key — payment đã có!).
4. 📝 **Backlog:** Circuit breaker pattern trong order-service cho payment calls.

---

# 🧪 Experiment 6: Cloud Map DNS Failure (Service Discovery Disruption)

**SEV-2** | **Blast Radius:** 2 ECS Services | **Thời gian:** ~25 phút

> Experiment 2 block ALL traffic bằng SG. Experiment 6 **chỉ phá service discovery** — payment task vẫn RUNNING nhưng order-service không tìm thấy nó qua DNS.

### 📚 Học được gì sau experiment này

- Hiểu **Cloud Map DNS resolution flow**: Order gọi `payment-service.ecommerce.local` → Cloud Map trả IP → HTTP request.
- Phân biệt **ConnectionError** (DNS fail / IP unreachable) vs **Timeout** (Exp 5) — app handle khác nhau không?
- Khám phá **DNS TTL cache**: Sau khi deregister, bao lâu thì DNS trả NXDOMAIN?
- Confirm lại **Zombie Task blind spot** từ Exp 2: task RUNNING nhưng DNS không trỏ tới nó → unreachable.
- Hiểu tại sao Cloud Map-only services cần **synthetic health check** (không có ALB health check).

### ⚠️ Bẫy thường gặp

- ❌ Deregister Cloud Map instance nhưng quên re-register khi rollback → payment biến mất khỏi DNS vĩnh viễn.
- ❌ DNS TTL cache → request đầu vẫn OK (cached IP) → nhầm tưởng inject fail.
- ❌ Nhầm Service ID (Cloud Map) với Service Name (ECS).

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

```bash
# 1. Cả 2 services RUNNING
for svc in payment-service order-service; do
  echo "=== $svc ==="
  aws ecs describe-services --cluster obs-cluster --services $svc \
    --query 'services[0].{Status:status, Running:runningCount}' --output table
done

# 2. Lấy Cloud Map namespace và service IDs
NAMESPACE_ID=$(aws ssm get-parameter --name "/obs/lab/compute/cloudmap_namespace_id" \
    --query 'Parameter.Value' --output text)
echo "Namespace ID: $NAMESPACE_ID"

# 3. List Cloud Map services trong namespace
aws servicediscovery list-services \
    --filters Name=NAMESPACE_ID,Values=$NAMESPACE_ID \
    --query 'Services[*].{Name:Name,Id:Id}' --output table
```

✅ **Kỳ vọng:** Thấy cả `payment-service` và `order-service` trong Cloud Map.

```bash
# 4. Lấy payment-service Cloud Map Service ID
PAYMENT_CM_SVC_ID=$(aws servicediscovery list-services \
    --filters Name=NAMESPACE_ID,Values=$NAMESPACE_ID \
    --query "Services[?Name=='payment-service'].Id" --output text)
echo "Payment Cloud Map Service ID: $PAYMENT_CM_SVC_ID"

# 5. List instances (IP addresses) registered cho payment
aws servicediscovery list-instances --service-id $PAYMENT_CM_SVC_ID \
    --query 'Instances[*].{Id:Id,IP:Attributes.AWS_INSTANCE_IPV4,Port:Attributes.AWS_INSTANCE_PORT}' \
    --output table
```

✅ Kỳ vọng: Ít nhất 1 instance với IP và port 5002.

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 6. Verify DNS resolution từ TRONG order-service container
ORDER_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name order-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $ORDER_TASK --container order-service \
    --interactive --command \
    "python -c \"
import socket
ip = socket.gethostbyname('payment-service.ecommerce.local')
print(f'DNS resolved: payment-service.ecommerce.local → {ip}')
\""

# 7. Lưu instance ID để rollback
PAYMENT_INSTANCE_ID=$(aws servicediscovery list-instances \
    --service-id $PAYMENT_CM_SVC_ID \
    --query 'Instances[0].Id' --output text)
echo "Instance ID to deregister: $PAYMENT_INSTANCE_ID"

# Lưu IP để re-register
PAYMENT_IP=$(aws servicediscovery list-instances \
    --service-id $PAYMENT_CM_SVC_ID \
    --query 'Instances[0].Attributes.AWS_INSTANCE_IPV4' --output text)
echo "Payment IP: $PAYMENT_IP"
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: DNS resolves OK, Instance ID = `$PAYMENT_INSTANCE_ID`, IP = `$PAYMENT_IP`.

---

## 💥 Phase 2: Inject Failure

```bash
# 8. Deregister payment-service instance khỏi Cloud Map
aws servicediscovery deregister-instance \
    --service-id $PAYMENT_CM_SVC_ID \
    --instance-id $PAYMENT_INSTANCE_ID

echo "⏰ $(date +%H:%M:%S) — Instance deregistered. DNS sẽ stale trong ~60s (TTL)."
```

> ⚠️ **QUAN TRỌNG:** ECS task payment-service VẪN RUNNING! Chỉ DNS record bị xóa → "Phantom service".

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Deregistered payment-service from Cloud Map.

---

## 🔍 Phase 3: Observe & Triage (The Investigation)

### Bước 3.1: Đợi DNS TTL expire (~60-120s)

```bash
# Kiểm tra DNS mỗi 15 giây
for i in $(seq 1 8); do
  echo "--- Check $i ($(date +%H:%M:%S)) ---"
  aws ecs execute-command --cluster obs-cluster \
      --task $ORDER_TASK --container order-service \
      --interactive --command \
      "python -c \"
import socket
try:
    ip = socket.gethostbyname('payment-service.ecommerce.local')
    print(f'RESOLVED: {ip} (still cached?)')
except socket.gaierror as e:
    print(f'NXDOMAIN: {e} (DNS propagated!)')
\""
  sleep 15
done
```

👁️ **Kết quả kỳ vọng:**
- Check 1-4: `RESOLVED: 10.x.x.x (still cached?)` — DNS TTL chưa expire
- Check 5-8: `NXDOMAIN: [Errno -2] Name or service not known` — DNS đã propagate

### Bước 3.2: Gọi order-service sau khi DNS fail

```bash
aws ecs execute-command --cluster obs-cluster \
    --task $ORDER_TASK --container order-service \
    --interactive --command \
    "python -c \"
import urllib.request, json, time
start = time.time()
try:
    data = json.dumps({'product_id': 'dns-test', 'quantity': 1}).encode()
    req = urllib.request.Request('http://localhost:5001/orders',
        data=data, headers={'Content-Type': 'application/json'}, method='POST')
    resp = urllib.request.urlopen(req, timeout=10)
    elapsed = time.time() - start
    print(f'Status: {resp.status}, Time: {elapsed:.2f}s')
    print(resp.read().decode()[:200])
except Exception as e:
    elapsed = time.time() - start
    print(f'ERROR after {elapsed:.2f}s: {e}')
\""
```

👁️ **Kết quả:**

| Scenario | Response time | Error type |
|---|---|---|
| DNS cached | ~5s | `ReadTimeout` (IP vẫn resolve, nhưng task có thể unreachable) |
| DNS expired | **< 1s** | `ConnectionError: Name or service not known` |

💡 **KEY INSIGHT:** `ConnectionError` fail **rất nhanh** (< 1s) so với `Timeout` (5s). Đây là thông tin quan trọng cho timeout budget design.

### Bước 3.3: Check CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
    --alarm-names obs-lab-payment-service-running-task-low \
                  obs-lab-order-service-running-task-low \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table
```

👁️ **Cả 2 alarms: OK.** Payment task vẫn RUNNING (nhưng unreachable qua DNS).

🚨 **ZOMBIE TASK CONFIRMED (lần 2):** Đây là blind spot từ Exp 2 — task RUNNING nhưng DNS không trỏ tới nó. Không có alarm nào fire.

### Bước 3.4: Check payment-service trực tiếp (vẫn alive!)

```bash
# Payment task VẪN RUNNING và healthy!
PAYMENT_TASK=$(aws ecs list-tasks --cluster obs-cluster \
    --service-name payment-service --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-cluster \
    --task $PAYMENT_TASK --container payment-service \
    --interactive --command \
    "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5002/health').read().decode())\""
```

👁️ Payment trả 200 OK. Service **alive** nhưng **invisible** qua DNS.

### Bước 3.5: Watch Telegram

👁️ **Kết quả:** Không có Telegram alert nào. Blind spot confirmed.

---

## 🔄 Phase 4: Rollback & Recovery

**Option A: Re-register thủ công**
```bash
aws servicediscovery register-instance \
    --service-id $PAYMENT_CM_SVC_ID \
    --instance-id $PAYMENT_INSTANCE_ID \
    --attributes AWS_INSTANCE_IPV4=$PAYMENT_IP,AWS_INSTANCE_PORT=5002
```

**Option B: Force redeploy (ECS tự re-register)**
```bash
aws ecs update-service --cluster obs-cluster \
    --service payment-service --force-new-deployment
```

Verify DNS đã trở lại (~60s sau re-register):
```bash
aws ecs execute-command --cluster obs-cluster \
    --task $ORDER_TASK --container order-service \
    --interactive --command \
    "python -c \"
import socket
ip = socket.gethostbyname('payment-service.ecommerce.local')
print(f'DNS restored: payment-service.ecommerce.local → {ip}')
\""
```

✅ **Kỳ vọng:** DNS resolve lại thành công.

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---|---|
| 1. Tại sao order nhận ConnectionError? | Cloud Map DNS trả NXDOMAIN cho `payment-service.ecommerce.local`. |
| 2. DNS TTL cache bao lâu? | ~60-120s (Cloud Map default). Trong thời gian cache, request vẫn tới IP cũ. |
| 3. ConnectionError vs Timeout? | ConnectionError fail < 1s (fast fail), Timeout fail ~5s. App hiện catch cùng `Exception` → không phân biệt. |
| 4. Zombie Task detected? | ✅ Payment RUNNING nhưng DNS deregistered → unreachable. Không alarm. |
| 5. Systemic Gap? | Cần **synthetic health check**: periodic DNS resolve + HTTP call → alarm nếu fail. |

**Action Items:**
1. 📝 **Critical:** Implement synthetic health check (Lambda / CloudWatch Synthetics) gọi `payment-service.ecommerce.local:5002/health` định kỳ.
2. 📝 **Important:** Phân biệt error types trong order-service: `ConnectionError` vs `Timeout` → metric riêng.
3. 📝 **Backlog:** DNS cache warm-up strategy: pre-resolve DNS on startup, periodic re-resolve.
4. 📝 **Backlog:** Evaluate chuyển sang ALB-backed services (có built-in health check) cho critical services.

---
# ============================================================
# PHASE 1.5: OBSERVABILITY BRIDGE — CHAOS DRILLS
# ============================================================
#
# Triết lý của Phase 1.5:
#   "Telemetry Pipeline là một distributed system khác."
#
# Nếu Phase 1 test "App có chết không?", thì Phase 1.5 test:
#   - "Khi App spam telemetry, pipeline có tự bảo vệ không?"
#   - "Khi pipeline chết, App có bị vạ lây không?"
#   - "Khi pipeline câm lặng, ta có BIẾT nó đang chết không?"
#
# Common theme: Mọi experiment trong Phase 1.5 đều KHÔNG trigger
# Telegram alert — đây chính là bài học lớn nhất:
#   🚨 "Who watches the watchmen?" — Chưa ai cả. Đó là gap cần fix.
# ============================================================

## 🔭 Phase 1.5 Pre-flight Checklist (Observability Pipeline)

Chạy TRƯỚC mọi experiment trong Phase 1.5. Đảm bảo telemetry pipeline đang KHỎE.

```bash
# 1. Verify ADOT sidecar đang RUNNING trong task
CLUSTER=obs-cluster
SERVICE=order-service
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].containers[].{Name:name,Status:lastStatus,Health:healthStatus,ExitCode:exitCode}' \
  --output table
# ✅ Kỳ vọng: 2 containers — order-service (RUNNING/HEALTHY) + aws-otel-collector (RUNNING/HEALTHY)

# 2. Verify ADOT health check endpoint (từ TRONG container app)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:13133/').read().decode())\""
# ✅ Kỳ vọng: {"status":"Server available","up_since":"...","uptime":"..."}

# 3. Verify AMP workspace đang nhận data (check active series)
WORKSPACE_ID=$(aws ssm get-parameter \
  --name "/obs/lab/observability/amp_workspace_id" \
  --query 'Parameter.Value' --output text)

aws amp list-workspaces --query "workspaces[?workspaceId=='$WORKSPACE_ID'].{Status:status}" \
  --output table
# ✅ Kỳ vọng: Status = ACTIVE

# 4. Verify X-Ray đang nhận traces (check sampling rules)
aws xray get-sampling-rules --query 'SamplingRuleRecords[0].SamplingRule.{RuleName:RuleName,Rate:FixedRate}' \
  --output table
# ✅ Kỳ vọng: Rule tồn tại

# 5. Verify IAM policy cho AMP RemoteWrite
TASK_ROLE_NAME=$(aws ssm get-parameter \
  --name "/obs/lab/security/ecs_task_role_name" \
  --query 'Parameter.Value' --output text)

aws iam list-role-policies --role-name $TASK_ROLE_NAME \
  --query 'PolicyNames[?contains(@, `amp`)]' --output table
# ✅ Kỳ vọng: Có policy chứa "amp" trong tên
```

❌ Nếu BẤT KỲ check nào fail → DỪNG LẠI. Fix pipeline trước khi drill.

---

## 🧪 Experiment 7: The Trace Storm (Sidecar Resource Contention)

**SEV-4** | **Blast Radius:** 1 ECS Task (in-place) | **Thời gian:** ~15 phút

### 📚 Học được gì sau experiment này

- Hiểu **Backpressure mechanism** của OTel Collector: `memory_limiter` processor bảo vệ sidecar khỏi OOM khi app spam telemetry.
- Kiểm chứng **Failure Isolation**: `essential = false` + `BatchSpanProcessor` (non-blocking) đảm bảo App KHÔNG bao giờ bị crash bởi chính telemetry của mình.
- Quan sát trực tiếp **Resource Contention** giữa App và Sidecar trong cùng một Fargate Task (dùng chung CPU/RAM pool).
- Hiểu tại sao thứ tự processors trong OTel config lại QUAN TRỌNG: `memory_limiter` PHẢI đứng đầu tiên.

**TTD target:** Không có Telegram alert (đây là expected behavior — hệ thống tự xử lý).

### ⚠️ Bẫy thường gặp

- ❌ Chạy storm script quá lâu (> 5 phút) → ADOT buffer đầy → drop spans → tưởng pipeline hỏng.
- ❌ Nhìn ADOT RAM tăng → hoảng → restart task → mất bằng chứng.
- ❌ Nhầm `SimpleSpanProcessor` (blocking) với `BatchSpanProcessor` (non-blocking) → script storm bị block, tưởng app bị ảnh hưởng.

### 🛑 Phase 0: Pre-flight Check

```bash
# Chạy Phase 1.5 Pre-flight Checklist ở trên
# Đảm bảo ADOT sidecar RUNNING + HEALTHY

# Ghi nhận baseline RAM của sidecar
aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].containers[?name==`aws-otel-collector`].{Name:name,Status:lastStatus}' \
  --output table
```

✅ Kỳ vọng: `aws-otel-collector = RUNNING`.

### 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 1. Ghi nhận ADOT self-metrics TRƯỚC storm (port 8888)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request, json
resp = urllib.request.urlopen('http://localhost:8888/metrics')
lines = resp.read().decode().split('\n')
# Filter for memory-related metrics
for l in lines:
    if 'otelcol_process_memory' in l or 'otelcol_exporter_sent' in l:
        print(l)
\""
# 📝 Ghi lại: baseline memory = ___MB, sent_spans = ___

# 2. Mở 3 terminals song song (chuẩn bị cho Phase 3)
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: ADOT healthy, memory = ___MB.

### 💥 Phase 2: Inject Failure (The Trace Storm)

Dùng ECS Exec vào app container (KHÔNG phải sidecar), chạy script Python tạo 50,000 spans càng nhanh càng tốt. Script tạo OTel SDK instance riêng, push thẳng vào `localhost:4317` (ADOT gRPC endpoint).

```bash
# Terminal 1: Inject — chạy trace storm generator
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry import trace
import time

# Tạo TracerProvider RIÊNG cho storm test (không ảnh hưởng app)
tp = TracerProvider()
# SimpleSpanProcessor = push ngay lập tức, không batch → maximum pressure
tp.add_span_processor(SimpleSpanProcessor(
    OTLPSpanExporter(endpoint='localhost:4317', insecure=True)
))
trace.set_tracer_provider(tp)
t = trace.get_tracer('storm-generator')

print('🌊 Starting trace storm: 50,000 spans...')
start = time.time()
for i in range(50000):
    with t.start_as_current_span('storm-span') as sp:
        sp.set_attribute('storm.index', i)
        sp.set_attribute('storm.type', 'trace-storm-drill')
        # Thêm padding để tăng payload size (~200 bytes/span)
        for j in range(5):
            sp.set_attribute(f'storm.padding.{j}', 'X' * 50)
    if i % 10000 == 0 and i > 0:
        elapsed = time.time() - start
        rate = i / elapsed
        print(f'  ⚡ {i:>6} spans | {elapsed:.1f}s | {rate:.0f} spans/sec')

elapsed = time.time() - start
print(f'✅ Done: 50,000 spans in {elapsed:.1f}s ({50000/elapsed:.0f} spans/sec)')
\""
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: 50,000 spans burst via SimpleSpanProcessor.

### 🔍 Phase 3: Observe & Triage (The Investigation)

Mở 3 terminals song song:

**Terminal 2: Watch ADOT Sidecar Logs (The Defense)**

```bash
LOG_GROUP="/ecs/otel-sidecar"  # Adjust to your actual log group
aws logs tail $LOG_GROUP --since 5m --format short --follow
```

👁️ **The SRE Lens** — Bạn sẽ thấy chuỗi events này:

```
[INFO]  otelcol@0.1.0 — Received span batch  {"spans": 1024}
[WARN]  memorylimiter — Memory usage is above limit. Dropping data.
        {"cur_mem_mib": 135, "limit_mib": 128, "spike_limit_mib": 32}
[WARN]  memorylimiter — Dropping spans due to memory pressure.
        {"dropped_spans": 4521}
[INFO]  memorylimiter — Memory usage recovered below limit.
        {"cur_mem_mib": 95, "limit_mib": 128}
```

💡 **THE "AHA!" MOMENT:**

`memory_limiter` hoạt động như một van xả áp suất:

- Khi RAM ADOT vượt 128 MiB (`limit_mib`) → bắt đầu drop spans
- Drop KHÔNG gây crash — ADOT vẫn sống, chỉ từ chối nhận thêm data
- Khi RAM giảm xuống dưới threshold → nhận data trở lại

Đây là **Backpressure pattern** — pipeline tự bảo vệ mình thay vì chết và kéo theo app.

**Terminal 3: Watch App Health (The Isolation Proof)**

```bash
# Liên tục gọi health check của app — PHẢI trả 200 suốt storm
while true; do
  STATUS=$(aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
    --container order-service --interactive \
    --command "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5001/health/live').status)\"" \
    --output text 2>/dev/null)
  echo "$(date +%H:%M:%S) — App health: $STATUS"
  sleep 5
done
```

👁️ **Kết quả:** `App health: 200` — liên tục, không gián đoạn.

💡 **Tại sao App không bị ảnh hưởng?** 3 lớp bảo vệ hoạt động đồng thời:

| Lớp | Cơ chế | Code |
|-----|--------|------|
| 1. App SDK | `BatchSpanProcessor` gom spans vào queue nội bộ. Khi queue đầy → drop spans, KHÔNG block app thread. | `shared/otel_setup.py` |
| 2. ADOT Sidecar | `memory_limiter` từ chối nhận data khi RAM > 128 MiB. App SDK nhận lỗi → drop. | `otel-config-aws.yaml.tftpl` |
| 3. ECS Fargate | `essential = false` — nếu sidecar crash, ECS KHÔNG giết app. | `task_definition.tf` |

**Terminal 1 (sau khi storm xong): Verify X-Ray received traces**

```bash
# Check X-Ray trace count trong 5 phút vừa qua
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 min ago' +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --filter-expression 'service.id(name: "storm-generator")' \
  --query '{TotalCount:ApproximateTotalCount, Traces: length(TraceSummaries)}' \
  --output json
```

👁️ **Kết quả:** X-Ray nhận được một phần spans (không phải toàn bộ 50,000). Phần còn lại bị `memory_limiter` drop.

📝 **Ghi vào notebook:**

```
[HH:MM:SS] Inject: 50,000 spans burst started
[HH:MM:SS] ADOT log: memory_limiter WARN — dropping data
[HH:MM:SS] App health: 200 (unaffected throughout)
[HH:MM:SS] Storm completed in ___s (___ spans/sec)
[HH:MM:SS] X-Ray received: ___ traces (partial — expected)
[HH:MM:SS] Telegram: NO alert (expected — system self-healed)
```

### 🔄 Phase 4: Rollback & Recovery

Không cần rollback — storm script tự kết thúc. ADOT `memory_limiter` tự phục hồi khi RAM giảm.

```bash
# Verify ADOT đã phục hồi (health check OK)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:13133/').read().decode())\""
# ✅ Kỳ vọng: {"status":"Server available", ...}
```

### 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---------|---------|
| 1. What happened? | App tạo 50,000 spans/sec → ADOT RAM tăng vượt 128 MiB. |
| 2. Why didn't ADOT crash (OOM Kill)? | `memory_limiter` processor drop spans khi RAM vượt threshold. |
| 3. Why didn't App crash? | `BatchSpanProcessor` trong OTel SDK là non-blocking. Queue đầy → drop, không block app thread. |
| 4. Why is processor ORDER important? | `memory_limiter` PHẢI đứng đầu pipeline. Nếu đứng sau batch, data đã được buffer vào RAM trước khi limiter kịp chặn. |
| 5. Systemic Gap? | Không có alert khi `memory_limiter` drop data. Team không biết telemetry bị mất một phần. |

**Action Items:**

- 📝 Backlog (Priority Medium): CloudWatch Metric Filter trên ADOT logs → đếm "Dropping data" → alarm khi rate > 0. Đây là meta-monitoring cho telemetry pipeline.
- 📝 Backlog: Thêm ADOT self-metrics (`localhost:8888/metrics`) vào Prometheus scrape → dashboard cho `otelcol_process_memory_rss`, `otelcol_exporter_send_failed_spans`.  
> 🛡️ Production Guardrail: Intelligent Drop (Tail-based Sampling)  
Trong production, chúng ta KHÔNG drop mù quáng (blind drop). 
Cần thêm `tail_sampling` processor vào `otel-config-aws.yaml.tftpl` ĐỨNG SAU `memory_limiter` và TRƯỚC `batch`:
- Luôn giữ lại 100% traces có `status_code=ERROR` hoặc `latency > 2s`.
- Chỉ sample 10% traces `OK` để tiết kiệm chi phí X-Ray.
> Bài học SRE: "Drop data là chấp nhận được, nhưng drop blind là tội lỗi. Phải drop có chủ đích."

---

## 🧪 Experiment 8: The Silent Blinder (Telemetry Pipeline Blackhole)

**SEV-2** | **Blast Radius:** 1 ECS Service (telemetry only) | **Thời gian:** ~20 phút

### 📚 Học được gì sau experiment này

- Hiểu "Who watches the watchmen?" — bài toán meta-monitoring mà 90% team bỏ qua.
- Phân biệt **Partial Telemetry Failure**: cắt `aps:RemoteWrite` → metrics mất nhưng traces (X-Ray) vẫn sống.
- Khám phá **Blind Spot** lớn nhất của Phase 1.5: không có alarm nào fire khi pipeline câm lặng.
- Hiểu cơ chế **SigV4 authentication** của ADOT: mỗi request được ký bằng IAM credentials của Task Role. Mất quyền = mất tất cả.

**TTD target:** ∞ (infinity) — KHÔNG có alert nào fire. Đây chính là bài học.

### ⚠️ Bẫy thường gặp

- ❌ Cắt NHẦM policy (gỡ cả X-Ray permissions) → không thấy được partial failure pattern.
- ❌ Force deploy sau khi gỡ policy → task mới có thể fail nếu execution role cũng bị ảnh hưởng. (Experiment này CHỈ gỡ inline policy trên Task Role, không ảnh hưởng execution role.)
- ❌ Mở X-Ray Console thấy traces vẫn có → kết luận "pipeline OK" → bỏ lỡ việc metrics đã mất hoàn toàn.

### 🛑 Phase 0: Pre-flight Check

```bash
# Chạy Phase 1.5 Pre-flight Checklist
# Đặc biệt verify:
#   - ADOT sidecar RUNNING + HEALTHY
#   - AMP workspace ACTIVE
#   - IAM policy "amp-remote-write" tồn tại trên Task Role

TASK_ROLE_NAME=$(aws ssm get-parameter \
  --name "/obs/lab/security/ecs_task_role_name" \
  --query 'Parameter.Value' --output text)
echo "Task Role: $TASK_ROLE_NAME"

# List inline policies
aws iam list-role-policies --role-name $TASK_ROLE_NAME \
  --query 'PolicyNames' --output table
# ✅ Kỳ vọng: Có policy tên "obs-ecs-task-amp-remote-write" (hoặc tương tự)
```

### 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 1. Ghi nhận policy ARN và nội dung hiện tại
POLICY_NAME=$(aws iam list-role-policies --role-name $TASK_ROLE_NAME \
  --query 'PolicyNames[?contains(@, `amp`)]' --output text)
echo "Policy Name: $POLICY_NAME"

# 2. Backup policy document (để rollback nếu cần)
aws iam get-role-policy --role-name $TASK_ROLE_NAME --policy-name $POLICY_NAME \
  --query 'PolicyDocument' --output json > /tmp/amp-policy-backup.json
cat /tmp/amp-policy-backup.json
# 📝 Lưu lại nội dung policy

# 3. Verify metrics đang flow vào AMP (generate 1 request để tạo metric)
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:5001/health/live').status)\""
# ✅ Kỳ vọng: 200

# 4. Check ADOT self-metrics — exporter status
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request
resp = urllib.request.urlopen('http://localhost:8888/metrics')
for l in resp.read().decode().split('\n'):
    if 'exporter_sent' in l or 'exporter_send_failed' in l:
        print(l)
\""
# 📝 Ghi lại: sent_metrics = ___, send_failed = 0
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: AMP policy attached, metrics flowing, send_failed = 0.

### 💥 Phase 2: Inject Failure (The IAM Blackhole for Telemetry)

Gỡ inline policy `aps:RemoteWrite` khỏi Task Role. ADOT sidecar sẽ nhận `AccessDenied` khi cố gắng push metrics vào AMP.

```bash
# Gỡ policy — ADOT mất quyền RemoteWrite vào AMP
aws iam delete-role-policy \
  --role-name $TASK_ROLE_NAME \
  --policy-name $POLICY_NAME

echo "⏰ $(date +%H:%M:%S) — Removed AMP RemoteWrite policy from Task Role"
echo "⚠️  IAM changes propagate in ~5-10 seconds. Next metric export cycle (10s) will fail."
```

⚠️ KHÔNG force deploy. IAM policy changes có hiệu lực ngay lập tức cho các API calls mới. ADOT sidecar đang chạy sẽ nhận `AccessDenied` ở lần export tiếp theo (mỗi 10 giây theo config `export_interval_millis: 10000`).

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Removed `aps:RemoteWrite` policy from Task Role.

### 🔍 Phase 3: Observe & Triage (The Investigation)

Mở 3 terminals:

**Terminal 1: Watch ADOT Logs (The Error Trail)**

```bash
LOG_GROUP="/ecs/otel-sidecar"
aws logs tail $LOG_GROUP --since 1m --format short --follow
```

👁️ **The SRE Lens** — Sau ~10-15 giây, bạn sẽ thấy:

```
[ERROR] prometheusremotewrite — Failed to export metrics
  {"error": "AccessDeniedException: User: arn:aws:sts::...:assumed-role/... is not authorized to perform: aps:RemoteWrite on resource: ..."}
[ERROR] prometheusremotewrite — Failed to export metrics
  {"error": "AccessDeniedException: ...", "dropped_metrics": 42}
[ERROR] prometheusremotewrite — Failed to export metrics  (repeats every 10s)
```

💡 **Partial Failure Pattern:**

Chỉ metrics bị ảnh hưởng. Traces (X-Ray) vẫn hoạt động bình thường vì:

- Metrics exporter dùng `aps:RemoteWrite` → DENIED
- Traces exporter dùng `xray:PutTraceSegments` → vẫn ALLOWED (policy khác)

Đây là thực tế phổ biến trong production: telemetry pipeline KHÔNG fail toàn bộ — nó fail từng phần, khiến việc phát hiện càng khó hơn.

**Terminal 2: Verify App Still Healthy (The Isolation)**

```bash
# App hoàn toàn không biết gì về việc telemetry bị mất
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request, json
# Health check
r1 = urllib.request.urlopen('http://localhost:5001/health/live')
print(f'App health: {r1.status}')
# Business endpoint
r2 = urllib.request.urlopen('http://localhost:5001/products')
data = json.loads(r2.read().decode())
print(f'Products: {len(data.get(\"products\", []))} items, source: {data.get(\"source\")}')
\""
```

👁️ **Kết quả:** `App health: 200`, `Products: 5 items` — App hoạt động hoàn toàn bình thường.

**Terminal 3: Check CloudWatch Alarms (The Blind Spot)**

```bash
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-order-service-memory-high \
                obs-lab-order-service-cpu-high \
                obs-lab-order-service-running-task-low \
                obs-lab-order-service-app-error-rate \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table
```

👁️ **Kết quả:** TẤT CẢ alarms đều OK.

🚨 **THE "AHA!" MOMENT — The Silent Blinder:**

| Signal | Status | Giải thích |
|--------|--------|-----------|
| ECS Task | RUNNING | App + sidecar đều alive |
| Memory/CPU | OK | Không có resource pressure |
| App Error Rate | OK | App không có lỗi |
| EventBridge | No event | Không có task stop, không có deployment fail |
| Telegram | Silence | KHÔNG có alert nào |

**Kết luận:** Hệ thống đang mù hoàn toàn về metrics, nhưng KHÔNG AI BIẾT. Nếu đây là production:

- Grafana dashboards trống trơn
- SLO burn rate không tính được
- Alerting rules không fire
- Team chỉ phát hiện khi user báo cáo sự cố và mở dashboard thấy... không có data

📝 **Ghi vào notebook:**

```
[HH:MM:SS] Inject: Removed AMP RemoteWrite policy
[HH:MM:SS] ADOT log: AccessDenied errors start (every 10s)
[HH:MM:SS] App health: 200 (unaffected)
[HH:MM:SS] X-Ray traces: STILL flowing (partial failure!)
[HH:MM:SS] CloudWatch Alarms: ALL OK
[HH:MM:SS] Telegram: NO alert — Blind Spot confirmed
[HH:MM:SS] TTD = ∞ (never detected by existing monitoring)
```

### 🔄 Phase 4: Rollback & Recovery

Dùng Terraform để heal (giống Experiment 1):

```bash
cd terraform/control-plane/lab
terraform apply -auto-approve
# Terraform sẽ tái tạo inline policy trên Task Role
```

Verify recovery:

```bash
# Đợi ~30s cho IAM propagation + 1 export cycle
sleep 30

# Check ADOT logs — errors should stop
aws logs tail $LOG_GROUP --since 1m --format short | tail -5
# ✅ Kỳ vọng: Không còn AccessDenied errors

# Check ADOT self-metrics — send_failed should drop to 0
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request
resp = urllib.request.urlopen('http://localhost:8888/metrics')
for l in resp.read().decode().split('\n'):
    if 'exporter_send_failed' in l:
        print(l)
\""
# ✅ Kỳ vọng: send_failed_metrics = 0 (hoặc không tăng thêm)
```

### 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---------|---------|
| 1. What happened? | Mất `aps:RemoteWrite` permission → ADOT không push được metrics vào AMP. |
| 2. Why didn't the app notice? | OTel SDK fire-and-forget. Export failure chỉ log warning, không ảnh hưởng app logic. |
| 3. Why was it a PARTIAL failure? | Metrics (AMP) và Traces (X-Ray) dùng IAM permissions KHÁC NHAU. Mất 1 cái, cái kia vẫn sống. |
| 4. Why didn't any alarm fire? | Không có alarm nào monitor telemetry pipeline health. Tất cả alarms chỉ monitor app + infra. |
| 5. Systemic Gap? | Meta-monitoring missing. Cần giám sát chính pipeline: ADOT export success rate, self-metrics, log error rate. |

**Action Items:**

- 📝 **Critical (Phase 1.5 follow-up):** CloudWatch Metric Filter trên ADOT Log Group:

```
  Filter pattern: "AccessDeniedException" OR "Failed to export"
  → CloudWatch Metric: "ADOTExportFailures"
  → Alarm: ADOTExportFailures > 0 for 2 minutes → Telegram CRITICAL
```

- 📝 **Important:** Thêm ADOT self-metrics endpoint (`localhost:8888`) vào Prometheus/AMP scrape config → dashboard cho pipeline health.
- 📝 **Backlog:** Implement Watchdog Pattern — một Lambda chạy mỗi 5 phút, query AMP cho metric `up{job="order-service"}`. Nếu không có data trong 10 phút → alert "Telemetry Pipeline Dead".
- 🛡️ Production Guardrail: The Dead Man's Switch (Meta-Monitoring)
Không tin tưởng tuyệt đối vào Log của Pipeline (vì khi pipeline nghẽn, log có thể bị FireLens drop).
Action Item: Tạo một Lambda Function (Heartbeat) chạy định kỳ 5 phút nhờ EventBridge.
Lambda dùng AWS SDK query thẳng vào AMP Workspace bằng PromQL: `count(up{job="order-service"})`.
- Nếu query ra kết quả > 0 -> Push metric `PipelineHealth = 1` về CloudWatch.
- Nếu Lambda fail / không có data -> Push `PipelineHealth = 0`.
- CloudWatch Alarm: `PipelineHealth < 1` với `treat_missing_data = breaching`.
> Bài học SRE: "Hệ thống giám sát phải có nhịp tim riêng. Khi nó im lặng, đó là dấu hiệu của cái chết."
---

## 🧪 Experiment 9: The Cardinality Bomb (FinOps Guardrail)

**SEV-3** | **Blast Radius:** 1 AMP Workspace (cost impact) | **Thời gian:** ~15 phút

### 📚 Học được gì sau experiment này

- Hiểu **Cardinality** — khái niệm quan trọng nhất trong Prometheus/AMP mà Junior SRE thường bỏ qua.
- Thấy trực tiếp cách một label có giá trị unique (như `user_id`) tạo ra hàng nghìn time series mới.
- Hiểu **Cost Model** của AMP: $0.03/10,000 samples ingested. High cardinality = cost explosion.
- Đánh giá hiệu quả của `filter` processor hiện tại — nó chỉ drop theo route, KHÔNG drop theo label cardinality.

**TTD target:** ∞ — Không có alert nào fire cho cardinality explosion.

### ⚠️ Bẫy thường gặp

- ❌ Chạy bomb quá lâu (> 2 phút) → AMP ingest hàng triệu samples → hóa đơn thực tế tăng.
- ❌ Nhầm time series (unique label combination) với samples (data points). 10,000 series × 1 sample/10s = 60,000 samples/hour.
- ❌ Quên rollback → bomb script chạy lại ở lần deploy sau.

### 🛑 Phase 0: Pre-flight Check

```bash
# Chạy Phase 1.5 Pre-flight Checklist
# Đặc biệt verify AMP workspace đang ACTIVE

# Check current active series count (baseline)
aws amp describe-workspace --workspace-id $WORKSPACE_ID \
  --query 'workspace.{Status:status, Alias:alias}' --output table
```

### 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 1. Ghi nhận ADOT filter config hiện tại
# (Đọc từ task definition environment variable)
aws ecs describe-task-definition \
  --task-definition $(aws ecs describe-services --cluster $CLUSTER \
    --services order-service --query 'services[0].taskDefinition' --output text) \
  --query 'taskDefinition.containerDefinitions[?name==`aws-otel-collector`].environment[?name==`AOT_CONFIG_CONTENT`].value' \
  --output text | grep -A 5 "filter"
# 📝 Ghi lại: filter/drop_health chỉ drop theo http.route

# 2. Generate 1 normal request để có baseline metric
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5001/products')\""
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: filter config noted, normal metrics flowing.

### 💥 Phase 2: Inject Failure (The Cardinality Bomb)

Dùng ECS Exec chạy script Python tạo metric với high-cardinality labels (mỗi sample có `user_id` = UUID khác nhau).

```bash
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry import metrics
import uuid, time

# Tạo MeterProvider riêng cho bomb test
reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint='localhost:4317', insecure=True),
    export_interval_millis=5000  # Export mỗi 5s
)
mp = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(mp)
meter = metrics.get_meter('cardinality-bomb-test')
counter = meter.create_counter('test.cardinality.bomb.total')

print('💣 Starting Cardinality Bomb: 5,000 unique time series...')
print('   Each series = unique (user_id, session_id) combination')
start = time.time()
for i in range(5000):
    # 🚨 HIGH CARDINALITY: mỗi iteration tạo 1 time series MỚI
    counter.add(1, {
        'user_id': str(uuid.uuid4()),       # ← UUID = infinite cardinality
        'session_id': str(uuid.uuid4()),    # ← UUID = infinite cardinality
        'service': 'cardinality-bomb-test',
        'environment': 'drill'
    })
    if i % 1000 == 0 and i > 0:
        elapsed = time.time() - start
        print(f'  💥 {i:>5} unique series created ({elapsed:.1f}s)')

# Chờ 2 export cycles để ADOT push data lên AMP
print('⏳ Waiting 15s for 3 export cycles...')
time.sleep(15)
elapsed = time.time() - start
print(f'✅ Bomb complete: 5,000 unique series in {elapsed:.1f}s')
print('⚠️  Each series will continue exporting every 5s until meter is destroyed.')
\""
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: 5,000 unique time series with UUID labels.

### 🔍 Phase 3: Observe & Triage (The Investigation)

**Terminal 1: Watch ADOT Logs (Processing Overhead)**

```bash
aws logs tail /ecs/otel-sidecar --since 1m --format short --follow
```

👁️ Bạn có thể thấy ADOT vẫn export bình thường — nó KHÔNG biết rằng labels có cardinality cao. OTel Collector không có built-in cardinality limiter (ở phiên bản hiện tại).

**Terminal 2: Calculate Cost Impact (The FinOps Lens)**

```bash
# Tính toán chi phí nếu bomb này chạy liên tục trong production
python3 -c "
series = 5000
export_interval = 10  # seconds (from ADOT config)
samples_per_hour = series * (3600 / export_interval)
cost_per_10k = 0.03  # USD per 10,000 samples (AMP pricing)
hourly_cost = (samples_per_hour / 10000) * cost_per_10k
monthly_cost = hourly_cost * 24 * 30

print('💰 Cardinality Bomb Cost Analysis:')
print(f'   Active series:        {series:,}')
print(f'   Samples/hour:         {samples_per_hour:,.0f}')
print(f'   Hourly cost:          \${hourly_cost:.2f}')
print(f'   Monthly cost:         \${monthly_cost:.2f}')
print(f'')
print(f'   ⚠️  Nếu Dev gắn user_id vào 10 metrics khác nhau:')
print(f'   Monthly cost × 10 =   \${monthly_cost * 10:.2f}')
print(f'')
print(f'   So sánh: 10 normal metrics (low cardinality) ≈ \$0.50/month')
print(f'   Cardinality bomb = {monthly_cost * 10 / 0.50:.0f}x cost increase!')
"
```

👁️ **Kết quả (ước tính):**

```
💰 Cardinality Bomb Cost Analysis:
   Active series:        5,000
   Samples/hour:         1,800,000
   Hourly cost:          $5.40
   Monthly cost:         $3,888.00

   ⚠️  Nếu Dev gắn user_id vào 10 metrics khác nhau:
   Monthly cost × 10 =   $38,880.00

   So sánh: 10 normal metrics (low cardinality) ≈ $0.50/month
   Cardinality bomb = 77760x cost increase!
```

🚨 **THE "AHA!" MOMENT — The FinOps Nightmare:**

Một dòng code vô hại:

```python
counter.add(1, {"user_id": user.id})  # Dev nghĩ: "Thêm label để filter cho tiện"
```

Có thể gây ra hóa đơn $38,880/tháng — gấp 77,000 lần chi phí bình thường.

**Terminal 3: Check Existing Guardrails**

```bash
# Kiểm tra filter config của ADOT — có chặn được cardinality bomb không?
# (Đọc từ AOT_CONFIG_CONTENT environment variable)
```

👁️ **Kết quả:** `filter/drop_health` CHỈ drop spans/metrics có `http.route == "/health/live"`. Nó HOÀN TOÀN KHÔNG chặn high-cardinality labels.

💡 **Gap Analysis:**

| Guardrail | Hiện tại | Cần có |
|-----------|---------|--------|
| Drop health check spans | ✅ `filter/drop_health` | — |
| Drop high-cardinality labels | ❌ Không có | `attributes` processor hoặc filter by label pattern |
| Alert on series count spike | ❌ Không có | CloudWatch Alarm on AMP `ActiveSeries` metric |
| Cost anomaly detection | ❌ Chưa setup | AWS Cost Anomaly Detection |

📝 **Ghi vào notebook:**

```
[HH:MM:SS] Inject: 5,000 unique series with UUID labels
[HH:MM:SS] ADOT: processing normally (no cardinality awareness)
[HH:MM:SS] Estimated monthly cost: $3,888
[HH:MM:SS] Existing filter: NOT blocking high-cardinality labels
[HH:MM:SS] Telegram: NO alert — FinOps blind spot confirmed
```

### 🔄 Phase 4: Rollback & Recovery

Script bomb tự kết thúc sau khi tạo 5,000 series. Khi Python process exit, `MeterProvider` bị destroy → không export thêm.

Tuy nhiên, AMP vẫn giữ 5,000 series này trong ~5 phút (stale series). Sau đó chúng tự động bị mark inactive.

```bash
# Verify: đợi 5 phút, check ADOT self-metrics
sleep 300

aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request
resp = urllib.request.urlopen('http://localhost:8888/metrics')
for l in resp.read().decode().split('\n'):
    if 'exporter_sent' in l and 'metric' in l:
        print(l)
\""
# ✅ Kỳ vọng: export rate trở lại baseline
```

### 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---------|---------|
| 1. What happened? | 5,000 unique time series được tạo với UUID labels → AMP ingest hàng triệu samples. |
| 2. Why didn't ADOT block it? | OTel Collector KHÔNG có built-in cardinality limiter. `filter` processor chỉ filter theo attribute value, không theo cardinality. |
| 3. Why is this dangerous in production? | Một Dev vô tình gắn `user_id` vào metric → hóa đơn AMP tăng 77,000x. Không có alert → phát hiện khi nhận hóa đơn cuối tháng. |
| 4. What's the cardinality rule? | Labels chỉ được có giá trị từ tập hữu hạn nhỏ (như `service_name`, `http_method`, `status_code`). TUYỆT ĐỐI KHÔNG gắn `user_id`, `order_id`, `session_id`, `request_id`. |
| 5. Systemic Gap? | Cần (1) cardinality guardrail ở ADOT, (2) AMP ActiveSeries alarm, (3) Cost Anomaly Detection. |

**Action Items:**

- 📝 **Critical:** AWS Budgets + Cost Anomaly Detection cho AMP service (setup trong Phase 3 — `budgets` module).
- 📝 **Important:** CloudWatch Alarm trên AMP metric `AWS/Usage > ActiveSeries` > threshold (ví dụ: 10,000 cho lab, 100,000 cho production).
- 📝 **Backlog:** Thêm `attributes` processor vào ADOT config để strip known high-cardinality labels:

```yaml
  processors:
    attributes/strip_cardinality:
      actions:
        - key: user_id
          action: delete
        - key: session_id
          action: delete
        - key: request_id
          action: delete
```
- 🛡️ Production Guardrail: Shift-Left FinOps & Sanitize Labels
Dev có thể vô tình gắn `user_id` (UUID) vào metric gây nổ hóa đơn AMP.
1. Runtime Guardrail: Thêm `transform/sanitize_labels` processor vào ADOT config để dùng Regex xóa bỏ mọi label có dạng UUID (`user_id`, `session_id`, `request_id`) TRƯỚC khi metric được push lên AMP.
2. FinOps Alarm: Tạo CloudWatch Alarm monitor metric `AWS/Usage` namespace, metric name `ActiveSeries`. Đặt threshold hard-limit (ví dụ: 10,000 series cho Lab) để alert sớm trước khi AWS tính tiền.
---

## 🧪 Experiment 10: The Zombie Sidecar (Non-Essential Container Death)

**SEV-2** | **Blast Radius:** 1 ECS Task (telemetry loss) | **Thời gian:** ~20 phút

### 📚 Học được gì sau experiment này

- Hiểu sống còn về `essential = false` trong ECS Task Definition: container không essential → khi chết, ECS KHÔNG restart nó.
- Khám phá **Zombie Sidecar pattern**: sidecar chết âm thầm, app vẫn chạy, telemetry mất vĩnh viễn cho đến lần deploy tiếp theo.
- Phân biệt với Experiment 1 (IAM Blackhole cho Execution Role): Exp 1 → task không start được → Circuit Breaker rollback. Exp 10 → sidecar chết GIỮA CHỪNG → không có cơ chế nào phát hiện.
- Hiểu tại sao container-level health check trong Task Definition chỉ mang tính informational, KHÔNG trigger restart.

**TTD target:** ∞ — Không có alert nào fire. Đây là blind spot nghiêm trọng nhất của Phase 1.5.

### ⚠️ Bẫy thường gặp
- ⚠️ BẪY CHẾT NGƯỜI (THE ECS HEALTH CHECK ILLUSION):
Nhiều SRE cấu hình block `healthCheck` cho ADOT Sidecar trong `task_definition.tf`:
```
  healthCheck = {
    command = ["CMD-SHELL", "wget ... http://localhost:13133/ || exit 1"]
  }
```
- 🚨 SỰ THẬT PHŨ PHÀNG: ECS KHÔNG BAO GIỜ restart một container dựa trên block `healthCheck` này! 
Khác với Kubernetes (nơi `livenessProbe` fail sẽ giết Pod), block `healthCheck` của ECS chỉ mang tính chất Informational (báo cáo `HEALTHY`/`UNHEALTHY` lên Console). Nếu ADOT bị crash process nhưng container vẫn sống (zombie), `wget` sẽ fail, ECS báo `UNHEALTHY`, nhưng Task vẫn RUNNING và ECS không làm gì cả.

- ❌ Nghĩ rằng ECS sẽ auto-restart non-essential container → SAI. ECS chỉ restart containers thông qua service-level mechanisms (ALB health check → task replacement), không phải container-level.
- ❌ Dùng `aws ecs stop-task` → dừng TOÀN BỘ task (cả app) → không phải experiment này.
- ❌ Kỳ vọng EventBridge `EssentialContainerExited` fire → SAI. Stop code này CHỈ fire khi essential container exit.

### 🛑 Phase 0: Pre-flight Check

```bash
# Chạy Phase 1.5 Pre-flight Checklist
# Verify ADOT sidecar đang RUNNING

aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].containers[].{Name:name,Status:lastStatus,Essential:essential}' \
  --output table
# ✅ Kỳ vọng:
#   order-service       | RUNNING | (không hiển thị = true mặc định)
#   aws-otel-collector  | RUNNING | false
```

### 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

```bash
# 1. Ghi nhận container details
aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].containers[].{Name:name,Status:lastStatus,Health:healthStatus,RuntimeID:runtimeId}' \
  --output table
# 📝 Ghi lại runtimeId của aws-otel-collector

# 2. Verify telemetry đang flow
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:13133/').read().decode()[:100])\""
# ✅ Kỳ vọng: {"status":"Server available",...}
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Both containers RUNNING, ADOT health OK.

### 💥 Phase 2: Inject Failure (The Assassination)

ECS Exec vào ADOT sidecar container và kill process chính (PID 1).

```bash
# Kill ADOT collector process
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container aws-otel-collector --interactive \
  --command "/bin/sh -c 'kill -9 1'"
```

⚠️ Nếu `kill` không có sẵn trong ADOT image, dùng alternative:

```bash
# Alternative: dùng Python (nếu có) hoặc /proc
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container aws-otel-collector --interactive \
  --command "/bin/sh -c 'cat /proc/1/cmdline && echo && echo Sending SIGKILL... && kill -KILL 1'"
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: `kill -9 1` on ADOT sidecar container.

### 🔍 Phase 3: Observe & Triage (The Investigation)

Mở 3 terminals:

**Terminal 1: Watch Task Status (The Zombie Revelation)**

```bash
# Check task status mỗi 10s
while true; do
  echo "=== $(date +%H:%M:%S) ==="
  aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
    --query 'tasks[0].containers[].{Name:name,Status:lastStatus,ExitCode:exitCode,Health:healthStatus}' \
    --output table
  echo ""
  sleep 10
done
```

👁️ **The SRE Lens** — Timeline bạn sẽ thấy:

| Thời điểm | order-service | aws-otel-collector |
|-----------|---------------|---------------------|
| T+0s | RUNNING / HEALTHY | RUNNING / HEALTHY |
| T+10s | RUNNING / HEALTHY | STOPPED / ExitCode: 137 |
| T+30s | RUNNING / HEALTHY | STOPPED / 137 |
| T+60s | RUNNING / HEALTHY | STOPPED / 137 |
| T+120s | RUNNING / HEALTHY | STOPPED / 137 |
| T+300s | RUNNING / HEALTHY | STOPPED / 137 |

🚨 **THE "AHA!" MOMENT — Non-Essential Containers Don't Restart:**

Sau 5 phút, sidecar VẪN STOPPED. ECS KHÔNG restart nó. Task VẪN RUNNING với app container alive.

Đây là **Zombie Sidecar pattern**:

- App container: sống, serve traffic bình thường
- Sidecar container: chết, không thu thập telemetry
- Task: RUNNING — dashboard xanh
- Telemetry: mất vĩnh viễn cho đến lần deploy tiếp theo

**Terminal 2: Verify App Still Works (The Isolation Proof)**

```bash
# App hoàn toàn không bị ảnh hưởng
aws ecs execute-command --cluster $CLUSTER --task $TASK_ARN \
  --container order-service --interactive \
  --command "python -c \"
import urllib.request, json
r = urllib.request.urlopen('http://localhost:5001/products')
data = json.loads(r.read().decode())
print(f'App: HEALTHY — {len(data[\"products\"])} products')

# Thử gọi ADOT health check — sẽ FAIL
try:
    urllib.request.urlopen('http://localhost:13133/', timeout=3)
    print('ADOT: HEALTHY')
except Exception as e:
    print(f'ADOT: DEAD — {e}')
\""
```

👁️ **Kết quả:**

```
App: HEALTHY — 5 products
ADOT: DEAD — <urlopen error [Errno 111] Connection refused>
```

**Terminal 3: Check EventBridge & Alarms (The Complete Blind Spot)**

```bash
# Check EventBridge — có event nào cho non-essential container exit không?
aws events list-rules --name-prefix obs-lab-ecs- \
  --query 'Rules[*].{Name:Name,State:State}' --output table

# Check alarms
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-order-service-running-task-low \
                obs-lab-order-service-memory-high \
                obs-lab-order-service-app-error-rate \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table
```

👁️ **Kết quả:**

- EventBridge rule `ecs-task-stopped-abnormal` filter `stopCode: EssentialContainerExited` → KHÔNG match (vì ADOT là non-essential)
- Tất cả alarms: OK (task vẫn RUNNING, CPU/Memory bình thường)
- Telegram: KHÔNG có alert

💡 **So sánh với Experiment 1 (IAM Blackhole):**

| Aspect | Exp 1 (Execution Role) | Exp 10 (Zombie Sidecar) |
|--------|------------------------|-------------------------|
| Container bị ảnh hưởng | Task không start được | Sidecar chết giữa chừng |
| Circuit Breaker | ✅ Trip → rollback | ❌ Không áp dụng |
| EventBridge event | ✅ `SERVICE_DEPLOYMENT_FAILED` | ❌ Không có event |
| Telegram alert | 🚨 CRITICAL | ❌ Silence |
| Phát hiện bởi | Monitoring | Không ai — cho đến khi deploy mới |

📝 **Ghi vào notebook:**

```
[HH:MM:SS] Inject: kill -9 1 on ADOT sidecar
[HH:MM:SS] Sidecar: STOPPED (ExitCode 137)
[HH:MM:SS] App: RUNNING (unaffected — essential=false works!)
[HH:MM:SS] T+60s: Sidecar still STOPPED (ECS does NOT restart)
[HH:MM:SS] T+120s: Sidecar still STOPPED
[HH:MM:SS] EventBridge: NO event (non-essential exit not captured)
[HH:MM:SS] Telegram: NO alert — Zombie Sidecar confirmed
[HH:MM:SS] TTD = ∞ (permanent telemetry loss until next deploy)
```

### 🔄 Phase 4: Rollback & Recovery

ECS KHÔNG auto-restart non-essential container. Recovery options:

**Option A: Force redeploy (Recommended — nhanh nhất)**

```bash
aws ecs update-service --cluster $CLUSTER \
  --service order-service --force-new-deployment
# ECS tạo task mới → cả app + sidecar đều fresh
```

**Option B: Stop task để service scheduler tạo task mới**

```bash
aws ecs stop-task --cluster $CLUSTER --task $TASK_ARN \
  --reason "Chaos Drill 10: Zombie sidecar recovery"
# Service scheduler sẽ tạo task mới để thay thế
```

Verify recovery:

```bash
# Đợi ~60s cho task mới start
sleep 60

NEW_TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --service-name order-service \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster $CLUSTER --tasks $NEW_TASK_ARN \
  --query 'tasks[0].containers[].{Name:name,Status:lastStatus,Health:healthStatus}' \
  --output table
# ✅ Kỳ vọng: Cả 2 containers = RUNNING / HEALTHY
```

### 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời |
|---------|---------|
| 1. What happened? | ADOT sidecar bị kill → container STOPPED (ExitCode 137). |
| 2. Why didn't ECS restart the sidecar? | `essential = false` → ECS KHÔNG restart non-essential containers. Chỉ dừng task nếu ESSENTIAL container exit. |
| 3. Why didn't EventBridge fire? | Rule filter `stopCode: EssentialContainerExited` → không match non-essential container exit. |
| 4. Why is this worse than Exp 8? | Exp 8 (IAM Blackhole): pipeline fail nhưng container alive → có thể recover bằng cách restore IAM. Exp 10: container DEAD → chỉ recover bằng redeploy. |
| 5. Systemic Gap? | Cần (1) monitoring cho non-essential container status, (2) cân nhắc đổi `essential = true` cho ADOT sidecar. |

**Action Items:**

- ✅ KEEP `essential = false` (Bảo vệ App khỏi bị kéo chết theo khi ADOT bị OOM do Trace Storm).
- ✅ IMPLEMENT "App-level Watchdog" (Suicide Pattern):
    - App (Python) sẽ tự spawn một background thread định kỳ 30s ping `http://localhost:13133/` (ADOT Health Extension). 
    - Nếu ping fail 3 lần liên tiếp, App tự gọi `os._exit(1)`. 
    - Lúc này, App container (vốn là `essential = true`) chết -> ECS Service Scheduler lập tức phát hiện `EssentialContainerExited` -> Spawn một Task mới hoàn toàn (App mới + Sidecar mới).
> Triết lý: "App mù với việc data được lưu ở đâu, nhưng phải tỉnh táo để biết các thành phần local của nó có đang sống sót hay không."

- 📝 **Important:** CloudWatch Metric Filter trên ECS Container Insights:

```
  Metric: ContainerStopped (filter: containerName = "aws-otel-collector")
  → Alarm: > 0 → Telegram CRITICAL
```

- 📝 **Backlog:** Khi migrate sang EKS (Phase 7), dùng DaemonSet cho ADOT Collector → tách biệt lifecycle khỏi app pod. Sidecar pattern trên EKS có thể dùng init container + restart policy.

---

## 🗄️ POD 2: STATEFUL CHAOS (Outline — Sẽ viết chi tiết ở Tuần 3-5)

Triết lý của POD 2: "State is the hardest part of distributed systems."
Nếu Phase 1 test "App có chết không?", thì POD 2 test:
- "Khi DB đổi DNS (failover), App có tự reconnect không?"
- "Khi Cache bốc hơi, DB có bị Connection Pool Exhaustion không?"
- "Khi Kafka Broker chết, Consumer có rebalance và commit offset an toàn không?"

### 🧪 Experiment 11: The DB Earthquake (RDS Multi-AZ Failover)
- **Blast Radius:** RDS + Order Service + Payment Service
- **Inject:** `aws rds reboot-db-instance --force-failover`
- **Observe:** X-Ray trace chỉ ra chính xác 60s gap khi DNS chuyển AZ. Đo `psycopg2.OperationalError` rate.
- **Success Criteria:** App tự reconnect thành công nhờ `retry_connect()`, `User Pain Score` < 5%.

### 🧪 Experiment 12: The Cache Avalanche (Redis Flush)
- **Blast Radius:** ElastiCache + Order Service + RDS
- **Inject:** `redis-cli FLUSHALL` (hoặc delete ElastiCache node)
- **Observe:** CloudWatch RDS CPU spike 80%+. Đo `db_pool_wait_duration_seconds`.
- **Success Criteria:** App không bị "Connection Pool Exhaustion" (nhờ DB_POOL_MAX sizing đúng).

### 🧪 Experiment 13: The Kafka Partition (MSK Broker Loss)
- **Blast Radius:** MSK + Inventory/Notification Workers
- **Inject:** Reboot 1 MSK Broker (hoặc block SG port 9092 của 1 broker)
- **Observe:** Partition Leader Election time, Consumer Group Rebalance logs.
- **Success Criteria:** Workers tự động resume consume từ offset cũ, không mất message.

### 🧪 Experiment 14: The Zombie Consumer (Stop Worker)
- **Blast Radius:** 1 Inventory Worker Task
- **Inject:** `aws ecs stop-task`
- **Observe:** Kafka Consumer Lag tăng đột biến, sau đó giảm xuống khi task mới spin up.
- **Success Criteria:** Graceful Shutdown handler commit offset TRƯỚC khi process exit (không duplicate).

### 🧪 Experiment 15: The Graceful Guillotine (ECS Rolling Update)
- **Blast Radius:** Toàn bộ Order Service (force new deployment)
- **Inject:** Deploy image tag mới (cùng version) để trigger rolling update
- **Observe:** Kafka buffer flush, DB pool close, SIGTERM handling.
- **Success Criteria:** Zero dropped Kafka messages, Zero ghost DB connections.
---
## 🌪️ POD 3: THE AWS CHAOS DOJO (Outline — Sẽ viết chi tiết ở Tuần 6-10)

Triết lý của POD 3: "Stop clicking, start automating."
Chuyển từ Chaos thủ công (AWS CLI) sang **AWS FIS (Fault Injection Simulator)** — vũ khí tối thượng của SRE production.

### 🧪 Experiment 16: The AZ Apocalypse (AWS FIS)
- **Blast Radius:** Toàn bộ resources trong 1 AZ (EC2, RDS, ElastiCache)
- **Tool:** AWS FIS Experiment Template (Terraform)
- **Observe:** ALB cross-zone routing, Multi-AZ resilience.
- **Success Criteria:** Hệ thống tự phục hồi sang AZ mới mà không cần human intervention.

### 🧪 Experiment 17: The Cascade Symphony (Full-stack)
- **Blast Radius:** Web UI → API GW → Order → Payment → DB
- **Inject:** Kết hợp FIS (Network Disruption) + Traffic Generator (Flash Sale scenario)
- **Observe:** End-to-end SLO impact, RFC 7807 propagation qua 4 layers.
- **Success Criteria:** Đo chính xác "User Pain Score" trong toàn bộ chuỗi cascade.

### 🧪 Experiment 18: The Secret Betrayal (Secrets Manager Rotation)
- **Blast Radius:** RDS + All Services
- **Inject:** Trigger manual secret rotation
- **Observe:** App auto-reconnect với new password (không cần restart).
- **Success Criteria:** Zero downtime trong quá trình rotation.

### 🧪 Experiment 19-21: (Stateful Chaos tái hiện bằng FIS)
- **Exp 19:** The Kafka Earthquake (MSK Broker Loss via FIS)
- **Exp 20:** The Cache Apocalypse (ElastiCache Node Failure via FIS)
- **Exp 21:** The Graceful Guillotine 2.0 (ECS Rolling Update via FIS)

---
# 📖 Glossary & Cheat Sheets (Iteration A++)

### ExitCode signatures — bảng định mệnh của mọi SRE

| ExitCode | Tên | Ý nghĩa | Nguôn nhìn đầu tiên |
|---|---|---|---|
| `null` | Birth failure | Container CHƯA bao giờ khởi động | IAM Role, ECR image tag, Secrets Manager |
| `0` | Normal exit | Process kết thúc bình thường | Thường do user / scheduler initiated |
| `1` | App error | Process thoát do exception chưa catch | App logs (CloudWatch), env vars, config |
| `137` | OOM Kill (SIGKILL) | Linux OOM Killer hoặc manual `kill -9` | Memory metrics, task definition memory limit |
| `139` | Segfault (SIGSEGV) | Memory violation (C/C++/Rust unsafe) | Application core dump, dependency version |
| `143` | Graceful SIGTERM | ECS scale-in gửi SIGTERM, container respect | Healthy — không phải failure |

### ECS Failure Quadrants (kết hợp từ 4 experiments)

| Failure type | Container state | CloudWatch Logs | EventBridge signal | Telegram alert |
|---|---|---|---|---|
| **Birth** (Exp 1, 3A) | Never started | ❌ Empty | `stopCode = TaskFailedToStart` | ⚠️ + 🚨 (sau circuit breaker) |
| **Runtime** (Exp 3B, Exp 4 future) | Started → died | ✅ Partial (logs cut off) | `stopCode = EssentialContainerExited`, exit 137/1 | ⚠️ + 🚨 |
| **Zombie** (Exp 2) | Running + healthy | ✅ Full (bình thường) | ❌ Không (Cloud Map-only) | ❌ **Blind spot** — không alert |
| **Deployment** (Exp 1 outer) | Old task survives | (Empty cho task mới) | `eventType = SERVICE_DEPLOYMENT_FAILED` | 🚨 ngay |

### Leading vs Lagging indicators

| Loại | Metric | Khi fire | Action |
|---|---|---|---|
| **Leading** | `MemoryUtilization > 85%` | Trước OOM | Right-size, profile memory, scale out |
| **Lagging** | `RunningTaskCount < 1` | Sau khi service chết | Page on-call, cứu service trước, RCA sau |
| **Awareness** | `CPUUtilization > 80%` 5min | Workload anomaly | Investigate, chưa cần act |

### CloudWatch Alarm states (junior thường nhầm)

| State | Nghĩa | Có gửi notification không? |
|---|---|---|
| `OK` | Metric trong threshold | Có — nếu có `ok_actions` |
| `ALARM` | Metric breached threshold và đủ `evaluation_periods` | Có — qua `alarm_actions` |
| `INSUFFICIENT_DATA` | Không đủ datapoint để đánh giá | Có — nếu có `insufficient_data_actions` (mặc định không) |

### `treat_missing_data` — 1 trong 3 điểm dễ sai nhất

| Value | Khi missing datapoint | Dùng cho |
|---|---|---|
| `notBreaching` | Coi như OK | Resource usage (Memory, CPU) — task tạm dừng không phải vấn đề |
| `breaching` | Coi như ALARM | RunningTaskCount, HealthyHostCount — metric mất = service chết |
| `ignore` | Giữ state cũ | Hiếm dùng |
| `missing` | INSUFFICIENT_DATA | Mặc định — thường gây lừa khều trong production |

### EventBridge `eventType` với `ECS Deployment State Change`

| eventType | Khi nào fire | Mức độ |
|---|---|---|
| `SERVICE_DEPLOYMENT_IN_PROGRESS` | Deployment bắt đầu | Info |
| `SERVICE_DEPLOYMENT_COMPLETED` | Thành công — ROLLOUT_COMPLETED | Info (nên log) |
| `SERVICE_DEPLOYMENT_FAILED` | Circuit breaker trip + rollback | **Alert critical** |

### `stopCode` enum cho ECS Task State Change

| stopCode | Mô tả | Alert? |
|---|---|---|
| `TaskFailedToStart` | Container chưa từng RUNNING (Birth) | ✅ Đã wire |
| `EssentialContainerExited` | Container chạy rồi exit (Runtime) | ✅ Đã wire |
| `UserInitiated` | `aws ecs stop-task` thủ công | ❌ Loại |
| `ServiceSchedulerInitiated` | Rolling deploy / scale-in | ❌ Loại |
| `SpotInterruption` | (nếu dùng Fargate Spot) | Tữ nhân nhức |

### Service Discovery — Cloud Map DNS vs ECS Service Connect

| Aspect | Cloud Map DNS (hiện tại) | ECS Service Connect (tương lai) |
|---|---|---|
| Cơ chế | DNS A record, TTL=10s | Envoy sidecar proxy |
| Zombie Task | ⚠️ Blind spot (Exp 2, 6) | ✅ Active health check |
| Cascading failure | ⚠️ App tự handle (Exp 5) | ✅ Envoy retry + outlier detection |
| Metrics | ❌ Không có sẵn | ✅ CloudWatch: error rate, P95 |
| Resource overhead | $0 | +256 CPU, +64MB per task |

> 📖 Concept guide + Terraform config + Migration path: [`ECS_SERVICE_CONNECT.md`](./ECS_SERVICE_CONNECT.md)

## 📖 Phase 1.5 Glossary Additions

### OTel Collector Processors — Thứ tự QUAN TRỌNG

| Processor | Vai trò | Nếu đặt sai thứ tự |
|-----------|---------|---------------------|
| `memory_limiter` | Chặn data khi RAM vượt threshold | Đặt sau `batch` → data đã buffer vào RAM trước khi limiter kịp chặn → OOM |
| `filter` | Drop data theo điều kiện | Đặt sau `batch` → tốn tài nguyên xử lý data rồi mới drop |
| `probabilistic_sampler` | Giữ X% traces | Đặt trước `filter` → sample trước khi drop health checks → lãng phí quota |
| `batch` | Gom data trước khi export | Đặt trước `memory_limiter` → buffer đầy RAM trước khi limiter chặn |

### Essential vs Non-Essential Containers

| Aspect | Essential (`true`) | Non-Essential (`false`) |
|--------|---------------------|--------------------------|
| Container exit → Task | Task STOPPED | Task continues |
| Container exit → Restart | Service scheduler tạo task mới | KHÔNG restart |
| EventBridge signal | `EssentialContainerExited` | Không có event |
| Use case | App container, critical sidecar | Logging agent, debug tools |
| Phase 1.5 recommendation | App container | ADOT sidecar → đổi sang `true` |

### Cardinality Rules (Prometheus/AMP)

| Label Type | Examples | Cardinality | Rule |
|------------|----------|-------------|------|
| Low (OK) | `service_name`, `http_method`, `status_code`, `operation` | < 100 values | ✅ Dùng thoải mái |
| Medium (Caution) | `endpoint`, `db_table`, `cache_key_prefix` | 100-1,000 values | ⚠️ Giới hạn, monitor |
| High (DANGER) | `user_id`, `session_id`, `request_id`, `order_id` | ∞ values | ❌ TUYỆT ĐỐI KHÔNG gắn vào metric |

### Meta-Monitoring Patterns

| Pattern | Mô tả | Implementation |
|---------|-------|-----------------|
| Watchdog | External system checks if telemetry is flowing | Lambda → query AMP `up{job="..."}` → alert nếu no data |
| Self-metrics | Pipeline exports its own health metrics | ADOT `localhost:8888/metrics` → scrape → alarm |
| Log-based alert | Alert on pipeline error logs | CloudWatch Metric Filter on ADOT Log Group |
| Dead man's switch | Pipeline MUST send heartbeat every N minutes | Custom metric → alarm nếu missing |
---

# 🔮 Roadmap experiments kế tiếp

| # | Tên | Status | Pod | Skill mới học được |
|---|---|---|---|---|
| **POD 1: The Illumination** | | | | |
| 1 | IAM Blackhole (Execution Role) | ✅ Done | — | EventBridge, Circuit Breaker |
| 2 | Network Partition (SG) | ✅ Done | — | Zombie Task, Cloud Map blind spot |
| 3 | Poison Config (Bad Image / OOM) | ✅ Done | — | ExitCode signatures |
| 3.5 | Memory Pressure Drill | ✅ Done | — | Leading indicator verify |
| 4 | Task Role Blackhole (Runtime IAM) | 📝 Written | — | Silent Killer, app-level gap |
| 4B | Order-Service Poison Config | 📝 Written | — | Alarm `for_each` verification |
| 5 | Cascading Failure (Payment Slow) | 📝 Written | — | Overlap zone, intermittent failure |
| 6 | Cloud Map DNS Failure | 📝 Written | — | DNS TTL, synthetic health check |
| 7-10 | Observability Bridge Series | 📝 Written | POD 1 | Backpressure, Meta-monitoring, FinOps |
| **POD 2: The Critical Path (Stateful)** | | | | |
| 11 | The DB Earthquake (RDS Failover) | 🔜 | POD 2 | `retry_connect`, DNS propagation |
| 12 | The Cache Avalanche (Redis Flush) | 🔜 | POD 2 | Cache miss storm, Pool exhaustion |
| 13 | The Kafka Partition (MSK Broker) | 🔜 | POD 2 | Leader election, Rebalance |
| 14 | The Zombie Consumer (Stop Task) | 🔜 | POD 2 | Consumer lag, Offset commit |
| 15 | The Graceful Guillotine (Rolling) | 🔜 | POD 2 | SIGTERM, Kafka flush, DB close |
| **POD 3: The Chaos Dojo (AWS FIS)** | | | | |
| 16 | The AZ Apocalypse (FIS) | 🔜 | POD 3 | Multi-AZ resilience, FIS Templates |
| 17 | The Cascade Symphony (Full-stack) | 🔜 | POD 3 | E2E SLO impact, User Pain Score |
| 18 | The Secret Betrayal (Rotation) | 🔜 | POD 3 | Zero-downtime rotation |
| 19-21 | Stateful Chaos via FIS | 🔜 | POD 3 | Automating chaos with FIS |
| **Phase 8: Day-2 Ops** | | | | |
| 22 | EKS/RDS Major Upgrade | 🔜 | Phase 8 | Blue/Green deployment |
| 23 | DR Drill (Route53 Failover) | 🔜 | Phase 8 | RTO measurement |

---

# 📚 Tham khảo

- **Module alerting:** [`../modules/alerting/`](../modules/alerting/) — SNS + Lambda Telegram.
- **Observability (EventBridge + Alarms):** [`../control-plane/lab/observability.tf`](../control-plane/lab/observability.tf)
- **ROADMAP tổng:** [`../ROADMAP.md`](../ROADMAP.md)
- **AWS docs:** [ECS Events](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_cwe_events.html) · [Stop codes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-error-codes.html) · [Container Insights metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)