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

# 2. 3 alarms ở state OK (không INSUFFICIENT_DATA)
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-payment-service-memory-high \
                obs-lab-payment-service-cpu-high \
                obs-lab-payment-service-running-task-low \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table

# 3. EventBridge rules ENABLED
aws events list-rules --name-prefix obs-lab-ecs- \
  --query 'Rules[*].{Name:Name,State:State}' --output table
```

Nếu bất kỳ check nào FAIL, **STOP** — sửa alerting trước, không drill.

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

Trong `data-plane/terraform.tfvars`, đổi image tag thành giá trị không tồn tại:

```hcl
# terraform.tfvars
image_tag = "this-tag-does-not-exist-v999"
```

Chạy:

```bash
cd terraform/data-plane
terraform apply -auto-approve
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 💥 Injected: Deployed non-existent image tag.

### Scenario B: Memory Starvation (OOM Kill)

Trong `data-plane/terraform.tfvars`, giảm memory xuống mức không đủ cho app:

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

Khôi phục config gốc trong `data-plane/terraform.tfvars`:

```hcl
# terraform.tfvars — khôi phục giá trị gốc
image_tag = "<your-working-tag>"   # e.g., "ecs-fargate-v1"
memory    = 512
```

```bash
cd terraform/data-plane
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

---

# 🔮 Roadmap experiments kế tiếp

| # | Tên | Status | Iteration | Skill mới học được |
|---|---|---|---|---|
| 1 | IAM Blackhole (Execution Role) | ✅ Done + alert wired | A | EventBridge, Circuit Breaker, IAM |
| 2 | Network Partition (SG) | ✅ Done (Blind Spot discovered) | A | Zombie Task, Cloud Map-only blind spot |
| 3 | Poison Config (Bad Image / OOM) | ✅ Done + alert wired | A | ExitCode signatures, leading vs lagging |
| 3.5 | **Memory Pressure Drill** (recurring) | ✅ Done | A | ECS Exec, leading indicator verify, alarm tuning |
| 4 | **Task Role Blackhole (Runtime IAM)** | 🔜 Next | B | Runtime IAM vs Birth IAM, app-level error handling |
| 5 | Cascading failure (Payment slow → Order timeout) | 🔜 | C (sau onboard Order) | Service-to-service timeout, retry storm |
| 6 | Cloud Map DNS failure | 🔜 | C | Service discovery resilience |
| 7 | AWS FIS AZ failure | 🔜 | Phase 8 (ROADMAP) | Multi-AZ recovery, native AWS chaos |

---

# 📚 Tham khảo

- **Module alerting:** [`../modules/alerting/`](../modules/alerting/) — SNS + Lambda Telegram.
- **Observability (EventBridge + Alarms):** [`../control-plane/lab/observability.tf`](../control-plane/lab/observability.tf)
- **ROADMAP tổng:** [`../ROADMAP.md`](../ROADMAP.md)
- **AWS docs:** [ECS Events](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_cwe_events.html) · [Stop codes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/stopped-task-error-codes.html) · [Container Insights metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)