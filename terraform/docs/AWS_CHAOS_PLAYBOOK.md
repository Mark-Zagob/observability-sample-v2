# 🌪️ AWS Chaos Playbook

*Tài liệu thực hành Chaos Engineering dành riêng cho AWS Reliability Lab. Áp dụng phương pháp "Verify, don't trust".*

---

## 🛡️ Nguyên tắc an toàn (The 3 Commandments)

1. **Always have a Stop Condition:** Mọi drill thủ công phải có Time-box (hẹn giờ) hoặc Script tự động Rollback.
2. **Start with the smallest Blast Radius:** Chỉ tác động lên 1 Task, 1 Rule, hoặc 1 AZ trước khi scale lên toàn hệ thống.
3. **Observe the Control Plane:** Khi App Logs bị ảnh hưởng, hãy nhìn vào ECS Events, CloudTrail và VPC Flow Logs.

---

# 🧪 Experiment 1: The IAM Blackhole (Task Execution Role)

**SEV-3** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~15 phút

---

## 🎯 Mục tiêu & SRE Mindset

Hiểu rõ sự khác biệt sống còn giữa **Task Execution Role** (ECS Agent dùng để kéo image, ghi log) và **Task Role** (App code dùng để gọi AWS API).

Kiểm chứng giả thuyết: *"Mất Execution Role, Workload sẽ không thể 'chào đời' (Birth Failure), khác hoàn toàn với việc App đang chạy thì bị crash (Runtime Failure)."*

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

### Bước 3.5 (Nâng cao): Terraform Drift Detection

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
1. Viết OPA Policy (Rego) chặn mọi PR Terraform cố tình xóa `AmazonECSTaskExecutionRolePolicy` khỏi ECS Task Execution Role.
2. Tạo CloudWatch Alarm / EventBridge Rule trên ECS Event `SERVICE_DEPLOYMENT_FAILED` → gửi SNS notification cho team.

---

# 🧪 Experiment 2: The Network Partition (Security Group Isolation)

**SEV-2** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~20 phút

---

## 🎯 Mục tiêu & SRE Mindset

Hiểu rõ sự khác biệt sống còn giữa **Liveness** (App có đang chạy không?) và **Readiness** (App có thể nhận traffic không?).

Kiểm chứng giả thuyết: *"Network Partition không làm App crash. Nó biến App thành một 'Zombie' – vẫn thở nhưng không ai nghe thấy tiếng gọi."*

---

## 🛑 Phase 0: Pre-flight Check (Steady State)

> *Mục tiêu: Đảm bảo ALB đang route traffic thành công xuống ECS Task.*

Mở Terminal và chạy:

```bash
# 1. Lấy DNS của ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names <your-project>-alb \
    --query 'LoadBalancers[0].DNSName' --output text)
echo "ALB DNS: $ALB_DNS"

# 2. Verify traffic đang thông suốt (Kỳ vọng: 200 OK hoặc 404 Not Found của API GW)
curl -I http://$ALB_DNS/health/live
```

✅ **Kỳ vọng:** HTTP Status 200 hoặc 404 (miễn là không phải 502/504).

---

## 📊 Phase 1: Baseline (Ghi nhận bằng chứng)

> *Mục tiêu: Chụp ảnh "hiện trường" Target Group khi hệ thống khỏe mạnh.*

```bash
# 3. Lấy Target Group ARN của payment-service
TG_ARN=$(aws elbv2 describe-target-groups \
    --names <your-project>-payment-service \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# 4. Check Health Status qua CLI
aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id, State:TargetHealth.State, Reason:TargetHealth.Reason}' \
    --output table
```

📝 **Ghi vào Incident Log:** `[HH:MM]` 🟢 Baseline: Target Group State = HEALTHY.

---

## 💥 Phase 2: Inject Failure (The Isolation)

Chúng ta sẽ dùng Terraform để gỡ bỏ "sợi dây cáp mạng" nối từ ALB vào App.

1. Mở file `terraform/modules/security/security_groups.tf`.
2. Tìm block `resource "aws_security_group_rule" "app_ingress_from_alb"` (hoặc rule cho phép ALB SG gọi vào App SG ở port 5002).
3. Comment out (hoặc xóa) block đó.
4. Chạy lệnh:

```bash
cd terraform/control-plane/lab
terraform apply -auto-approve
```

---

## 🔍 Phase 3: Observe & Triage (The "Zombie" Investigation)

> Đây là lúc tư duy SRE của bạn được thử thách. HÃY MỞ 3 TERMINAL để thấy bức tranh toàn cảnh.

### Terminal 1: Giả lập User Traffic (The Symptom)

Chạy vòng lặp curl để bắn request liên tục vào ALB:

```bash
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_DNS/api/payment/health; sleep 1; done
```

👁️ **The SRE Lens:**

Ban đầu bạn thấy 200. Khoảng 60-90s sau khi chạy `terraform apply`, terminal sẽ liên tục bắn ra `502` (Bad Gateway) hoặc `504` (Gateway Timeout).

💡 **Tại sao?** ALB cố gắng gửi Health Check và Traffic xuống App, nhưng bị VPC Router chặn đứng (Drop) ở tầng Network.

### Terminal 2: Check ALB Target Health (The Control Plane)

```bash
aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id, State:TargetHealth.State, Reason:TargetHealth.Reason, Desc:TargetHealth.Description}' \
    --output table
```

👁️ **Kết quả:**

- `State: unhealthy`
- `Reason: Health checks failed`
- `Description: Health check failed with status code 0` (hoặc Timeout)

💡 ALB đã nhận ra "cư dân" này không còn phản hồi và ngừng route traffic mới vào nó.

### Terminal 3: Check ECS Task Status (The Illusion / Bẫy lớn nhất)

```bash
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services payment-service \
    --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount, Deployments:deployments[*].{Status:status, Running:runningCount, Rollback:rollBack}}' \
    --output json
```

👁️ **Kết quả (Cú sốc cho Junior SRE):**

- `Status: ACTIVE`
- `Running: 1`
- `Rollback: false` (Hoặc Circuit Breaker KHÔNG kích hoạt)

🚨 **THE "AHA!" MOMENT (Đính chính hiểu lầm tai hại):**

Nhiều người nghĩ rằng `deployment_circuit_breaker` sẽ tự động Rollback khi ALB báo Unhealthy. **SAI!**

- Circuit Breaker CHỈ hoạt động trong quá trình **DEPLOYMENT** (khi Task mới đang cố gắng replace Task cũ).
- Nếu Task ĐANG CHẠY ỔN ĐỊNH mà bạn đột ngột cắt Network (SG Rule), ECS Control Plane KHÔNG giết Task đó, và KHÔNG Rollback.
- Dưới góc nhìn của ECS Agent: Container vẫn đang chạy (Liveness Probe = Pass, Process PID vẫn tồn tại). ECS không biết gì về việc AWS VPC Network đang drop gói tin.
- **Kết luận:** Bạn vừa tạo ra một **Zombie Task**. Nó vẫn tốn tiền CPU/RAM của bạn, vẫn ghi log "Server started on port 5002", nhưng không phục vụ bất kỳ user nào.

---

## 🔄 Phase 4: Rollback & Recovery

Khôi phục "sợi dây cáp mạng" bằng Terraform.

1. Uncomment lại block `app_ingress_from_alb` trong `security_groups.tf`.
2. Chạy:

```bash
terraform apply -auto-approve
```

3. Quan sát Terminal 1 (Vòng lặp curl):
   - Đợi khoảng 30s - 60s (Thời gian AWS propagate SG Rule + ALB Health Check Interval 30s × 3 lần success).
   - Mã HTTP sẽ nhảy từ `502` trở lại về `200`.

4. Verify Target Group:

```bash
aws elbv2 describe-target-health --target-group-arn $TG_ARN --query 'TargetHealthDescriptions[*].TargetHealth.State'
# Kỳ vọng: ['healthy']
```

---

## 🧠 Phase 5: Post-Mortem & The 5 Whys

| Câu hỏi | Trả lời của bạn (Gợi ý) |
|---------|------------------------|
| 1. Why did users get 502 Bad Gateway? | ALB không thể kết nối TCP/HTTP tới ECS Task để forward request. |
| 2. Why couldn't ALB reach the Task? | Security Group Inbound Rule từ ALB SG đến App SG bị xóa. VPC Network drop gói tin. |
| 3. Why didn't ECS restart or rollback the Task? | ECS chỉ kiểm tra Liveness (Container có đang chạy process không?). Nó không tự động kiểm tra Readiness (Network có thông không?) đối với các Task đã chạy ổn định từ trước. |
| 4. Why is Network Partition dangerous? | Nó tạo ra "Zombie Tasks" – chiếm dụng tài nguyên, làm sai lệch metrics (App báo healthy, nhưng Business metric = 0), và gây khó khăn khi debug nếu chỉ nhìn vào ECS Console. |
| 5. Systemic Gap (Production)? | Nếu AI/Dev vô tình xóa SG Rule trên Prod, làm sao phát hiện ngay lập tức? |

**Action Item (Phase 3/8):**

1. Cần một CloudWatch Alarm dựa trên metric `HTTPCode_Target_5XX_Count` của ALB.
2. (Nâng cao) Cấu hình App tự động tắt (Crash) nếu nó phát hiện không nhận được request nào trong 5 phút (Self-preservation pattern).

---

# 🧪 Experiment 3: The Poison Config (Container Runtime Failure)

**SEV-3** | **Blast Radius:** 1 ECS Service (`payment-service`) | **Thời gian:** ~20 phút

---

## 🎯 Mục tiêu & SRE Mindset

Hiểu rõ sự khác biệt giữa **3 loại failure** trong ECS Task lifecycle:

| # | Loại failure | Khi nào xảy ra | Ví dụ | CloudWatch Logs? |
|---|---|---|---|---|
| 1 | **Birth Failure** (Experiment 1) | Trước khi container khởi tạo | IAM thiếu quyền pull image/secrets | ❌ Trống hoàn toàn |
| 2 | **Runtime Failure** (Experiment 3A) | Container chạy rồi nhưng app crash ngay | Bad config, missing env var, OOM Kill | ✅ Có vài dòng log trước khi chết |
| 3 | **Zombie Failure** (Experiment 2) | Container chạy ổn định nhưng bị cô lập | Network partition, SG rule bị xóa | ✅ App vẫn ghi log bình thường |

Kiểm chứng giả thuyết: *"Khi container chạy được nhưng app crash ngay, Circuit Breaker vẫn bảo vệ — nhưng tín hiệu diagnostic hoàn toàn khác Birth Failure. SRE phải biết nhìn đúng chỗ."*

Experiment này có **2 kịch bản** (chọn 1 hoặc làm cả 2):
- **Scenario A:** Deploy image tag không tồn tại → Image Pull Failure
- **Scenario B:** Set memory quá thấp → OOM Kill

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

1. **CI/CD Gate:** Thêm bước `aws ecr describe-images --image-ids imageTag=$TAG` trong pipeline để xác nhận image tồn tại trước khi `terraform apply`.
2. **Resource Baseline:** Chạy load test trên local/staging để xác định baseline memory usage, set Fargate memory = `baseline × 1.5` (headroom).
3. **CloudWatch Alarm:** Tạo alarm trên metric `MemoryUtilization` > 85% để cảnh báo TRƯỚC khi OOM xảy ra.
4. **Diagnostic Cheat Sheet:** Lưu bảng ExitCode signatures (`null` / `137` / `1`) vào team runbook để triage nhanh.