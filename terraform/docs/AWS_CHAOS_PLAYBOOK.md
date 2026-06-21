# 🌪️ AWS Chaos Playbook

*Tài liệu thực hành Chaos Engineering dành riêng cho AWS Reliability Lab. Áp dụng phương pháp "Verify, don't trust".*

---

## 🛡️ Nguyên tắc an toàn (The 3 Commandments)

1. **Always have a Stop Condition:** Mọi drill thủ công phải có Time-box (hẹn giờ) hoặc Script tự động Rollback.
2. **Start with the smallest Blast Radius:** Chỉ tác động lên 1 Task, 1 Rule, hoặc 1 AZ trước khi scale lên toàn hệ thống.
3. **Observe the Control Plane:** Khi App Logs bị ảnh hưởng, hãy nhìn vào ECS Events, CloudTrail và VPC Flow Logs.

---

## 🧪 Experiment 1: The IAM Blackhole (Task Execution Role)

**Mục tiêu:** Hiểu rõ sự khác biệt giữa `Task Role` (App dùng) và `Task Execution Role` (ECS Agent dùng). Kiểm chứng cơ chế tự phục hồi của ECS Fargate.

**Blast Radius:** 1 ECS Service (`payment-service`).

**Stop Condition:** Khôi phục IAM Policy ngay lập tức sau khi quan sát xong ECS Events.

### 🛠️ Steps to Inject

1. Mở AWS Console → IAM → Roles → Tìm role có tên `<project_name>-ecs-task-execution`.
2. Ở tab **Permissions**, tìm policy `AmazonECSTaskExecutionRolePolicy` (hoặc custom policy đọc Secrets Manager).
3. Bấm **Remove** (Gỡ bỏ) policy này khỏi Role.
4. Mở ECS Console → Cluster → `payment-service` → Bấm **Update Service** → Tích vào `Force new deployment` → Bấm Create.

### 👁️ What to Observe (The SRE Lens)

1. **ECS Console (Tab Events):** Bạn sẽ KHÔNG thấy Task mới chuyển sang `RUNNING`. Thay vào đó, sau khoảng 1–2 phút, ECS Events sẽ bắn ra lỗi:

   > *"service payment-service was unable to place a task... Reason: AccessDeniedException. You are not authorized to perform: logs:CreateLogStream / ecr:GetAuthorizationToken"*

2. **CloudWatch Logs:** Hoàn toàn trống trơn (vì Task chết trước khi App kịp code log).
3. **AWS CloudTrail (Event History):** Tìm kiếm Event `AssumeRole` hoặc `AccessDenied` để thấy ECS Agent đang bị IAM chặn đứng như thế nào.

### 🔄 Rollback

1. Vào lại IAM Role → **Add permissions** → Attach lại `AmazonECSTaskExecutionRolePolicy` và các policy cần thiết.
2. ECS Service sẽ tự động nhận ra sự thay đổi, spawn Task mới và Task sẽ chuyển sang `RUNNING`.

### 🧠 Post-Mortem & Learnings

- **Bài học:** Task Execution Role là "giấy thông hành" để ECS Agent kéo image và tạo log. Mất nó, Workload không thể sinh ra (**Birth failure**), khác với việc App đang chạy thì bị crash (**Runtime failure**).
- **Platform Guardrail:** Đây là lý do Phase 3 (OPA Conftest) sẽ chặn mọi PR Terraform cố tình xóa bỏ IAM Role attachment của ECS Services.

---

## 🧪 Experiment 2: The Network Partition (Security Group Isolation)

**Mục tiêu:** Kiểm chứng `deployment_circuit_breaker` (Lá chắn đã fix ở Step 1) và cách ALB Health Check điều phối Traffic.

**Blast Radius:** Luồng traffic từ ALB vào `payment-service`.

**Stop Condition:** Add lại Inbound Rule ngay khi ALB báo Target Unhealthy.

### 🛠️ Steps to Inject

1. Mở file `terraform/modules/security/security_groups.tf`.
2. Tìm block `resource "aws_security_group_rule" "app_ingress_from_alb"`.
3. **Comment out** (hoặc xóa) block này.
4. Chạy `terraform apply`. (AWS sẽ thu hồi quyền ALB gọi vào App SG).

### 👁️ What to Observe (The SRE Lens)

1. **EC2 Console → Target Groups:** Chọn Target Group của `payment-service`. Bạn sẽ thấy Health Status chuyển từ `Healthy` sang `Unhealthy` (do ALB không thể gửi gói tin TCP/HTTP Health Check vào App).

2. **ECS Console → Service `payment-service`:**
   - Nếu bạn đã fix **Bom #2 (Deployment Circuit Breaker)**: ECS sẽ phát hiện Task mới không nhận được traffic hoặc Health Check fail, nó sẽ tự động **Rollback** về Task Definition cũ (nếu có) hoặc giữ nguyên Task cũ và báo lỗi `DEPLOYMENT_FAILED`.
   - *Lưu ý:* Nếu `payment-service` không gắn ALB (chỉ dùng Cloud Map nội bộ), Drill này sẽ không ảnh hưởng đến Health Check của ECS, mà chỉ chặn các service khác (như API Gateway) gọi đến nó qua Cloud Map DNS.

3. **VPC Flow Logs (Nếu đã bật):** Query trên Athena hoặc CloudWatch Logs Insights:

```sql
   SELECT * FROM vpc_flow_logs
   WHERE dstport = 5002 AND action = 'REJECT'
```

   Bạn sẽ thấy hàng loạt gói tin từ ALB bị `REJECT` ở tầng Network.

### 🔄 Rollback

1. Uncomment lại block `app_ingress_from_alb` trong `security_groups.tf`.
2. Chạy `terraform apply`. AWS SG Rule được tái tạo, ALB ngay lập tức probe lại và đánh dấu Target là Healthy.

### 🧠 Post-Mortem & Learnings

- **Bài học:** Security Group hoạt động ở tầng Stateful Firewall. Việc xóa Rule không làm sập App, mà làm App bị **"cô lập" (Network Partition)**.
- **SRE Mindset:** Trong các hệ thống Microservices, Network Partition nguy hiểm hơn Service Crash, vì App vẫn nghĩ mình đang `RUNNING` (Liveness Probe pass) nhưng thực tế không nhận được request nào (Readiness Probe fail).