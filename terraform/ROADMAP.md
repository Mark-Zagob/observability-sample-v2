# 🗺️ AWS Reliability Lab - Master Roadmap (Workload & Platform Driven)

Tài liệu này là "Kim Chỉ Nam" kết hợp giữa **Application Expansion** (10 Services) và **AWS Terraform Playbook** (18 Modules). 
Mục tiêu tối thượng: Xây dựng một Internal Developer Platform (IDP) thực thụ, nơi hạ tầng sinh ra để phục vụ Workload và tự động hóa việc tuân thủ Compliance.

## 📜 4 Nguyên Tắc Bất Di Bất Dịch (The 4 Iron Rules)
1. **No Infra without Workload:** Mọi module hạ tầng mới (RDS Proxy, MSK, ElastiCache) chỉ được build khi có ít nhất 1 Service cần nó.
2. **Chaos is a Feature:** Build xong module nào, phải "phá" (Chaos Drill) module đó ngay (Dùng AWS FIS hoặc thủ công).
3. **OTel-Native Bridge:** Application code chỉ biết push OTLP. Hạ tầng AWS (ADOT Collector) sẽ route về AMP (Prometheus), X-Ray, CloudWatch. **Tuyệt đối không tự host Loki/Tempo trên AWS** để tránh làm "Storage Admin".
4. **Control Plane vs Data Plane Boundary:** 
   - *Control Plane (Terraform):* VPC, EKS Cluster, RDS, IAM, OIDC. (Tốc độ thay đổi: Tuần/Tháng).
   - *Data Plane (ArgoCD/GitOps):* Deployments, Services, Ingress, HPA. (Tốc độ thay đổi: Giờ/Phút).

---

## 🚀 PHASE 1: THE SYNC TRACER BULLET (ECS Fargate)
**Mục tiêu:** Đưa 4 services cốt lõi (Web UI, API GW, Order, Payment) chạy trên ECS Fargate. Hiểu về AWS Networking, IAM Task Role và ALB.
**Thời gian:** 2 Tuần

### 🧩 Modules triển khai (Playbook)
- [ ] `ecr` (Module 9): Lifecycle policy, Image scanning.
- [ ] `loadbalancer` (Module 11): ALB Internet-facing, Target Groups, ACM (DNS validation).
- [ ] `compute/ecs-fargate` (Phase 8B): ECS Cluster, Task Definitions.
- [ ] *Update* `vpc-endpoints` (Module 2): Bật ECR Interface Endpoints (để Fargate pull image không tốn phí NAT).

### 📦 Workload Onboard
- [ ] Build & Push 4 images lên ECR.
- [ ] Wire ALB -> API Gateway -> Order/Payment.
- [ ] Inject `DATABASE_URL` từ Secrets Manager vào ECS Task qua IAM Task Role.

### 💥 SRE / Chaos Drill
- [ ] **Drill 1:** Revoke `ecr:GetAuthorizationToken` từ Task Execution Role -> Quan sát Task stuck ở `PENDING`.
- [ ] **Drill 2:** Tắt SG Inbound từ ALB -> ECS -> Quan sát ALB báo `502 Bad Gateway`.

### ✅ Definition of Done (DoD)
- [ ] `curl https://<ALB_DNS>/health/live` trả về 200 OK (qua HTTPS).
- [ ] VPC Flow Logs (Athena) xác nhận traffic ECR pull đi qua VPC Endpoint, KHÔNG qua NAT Gateway.

---

## 🗄️ PHASE 2: THE STATEFUL & ASYNC BACKBONE
**Mục tiêu:** Giải quyết Cache, Message Broker và hoàn thiện 6 services cơ bản.
**Thời gian:** 2 Tuần

### 🧩 Modules triển khai
- [ ] `cache` (Module 5): ElastiCache Redis (Multi-AZ, Auth Token).
- [ ] `streaming` (Module 6): MSK Kafka (KRaft, 2 brokers).
- [ ] *Update* `vpc-endpoints`: Thêm Secrets Manager, SSM Endpoints.

### 📦 Workload Onboard
- [ ] Deploy Notification Worker & Inventory Worker (Kafka Consumers).
- [ ] Wire Redis URL, test Cache-Aside pattern.

### 💥 SRE / Chaos Drill
- [ ] **Drill 1 (Cache Miss Storm):** Flush Redis -> Quan sát CloudWatch RDS CPU spike.
- [ ] **Drill 2 (MSK Nightmare):** Kill 1 MSK Broker -> Quan sát Partition Leader Election và Consumer Lag.
- [ ] **Drill 3 (Graceful Shutdown):** ECS Stop Task Worker -> Verify Kafka offset được commit trước khi chết (SIGTERM).

### ✅ Definition of Done (DoD)
- [ ] End-to-end flow: User mua hàng -> Order -> Kafka -> Workers -> DB.
- [ ] Verify MSK traffic KHÔNG đi qua NAT Gateway.

---

## 🛡️ PHASE 3: THE PLATFORM SHIELD & PR-DRIVEN IaC
**Mục tiêu:** Chuyển dịch từ "ClickOps/Local Apply" sang **PR-Driven Infrastructure**. Bảo vệ hạ tầng trước khi scale.
**Thời gian:** 1.5 Tuần

### 🧩 Modules triển khai
- [ ] `bastion` (Module 12): EC2 + SSM Session Manager (No SSH).
- [ ] `cicd` (Module 13): OIDC Provider, GitHub Actions IAM Roles (Plan vs Apply).
- [ ] `budgets` (Module 15): AWS Budgets + Cost Anomaly Detection.

### 📦 Platform Onboard
- [ ] **Shift-Left:** Chặn `terraform apply` local. Bắt buộc push code -> GHA Plan -> OPA Conftest Scan -> PR Comment -> Merge -> Apply.
- [ ] Dùng SSM Session Manager qua Bastion để nhảy vào RDS/MSK debug (thay vì mở port 5432 ra Internet).

### 💥 SRE / Chaos Drill
- [ ] **Drill 1 (OPA Block):** Cố tình mở port 22 trên Security Group trong PR -> OPA block PR.
- [ ] **Drill 2 (FinOps Alert):** Bật Flow Logs ALL traffic + 3 NAT Gateways -> Chờ AWS Budgets bắn alert email.

### ✅ Definition of Done (DoD)
- [ ] 100% infra changes đi qua PR và OPA scan.
- [ ] Connect thành công vào RDS từ Bastion qua SSM (không dùng SSH key).

---

## 🔐 PHASE 4: EXPANSION - SECURITY & CONNECTION POOLING
**Mục tiêu:** Onboard Auth Service và giải quyết bẫy "Connection Exhaustion" trước khi thêm 4 services nữa.
**Thời gian:** 2 Tuần

### 🧩 Modules triển khai
- [ ] `rds-proxy` (Module 8): RDS Proxy (Transaction mode, IAM Auth). *So sánh thực tế với self-hosted PgBouncer.*
- [ ] *Update* `database`: Tạo thêm `auth_db` và `shipping_db` trên cùng RDS Instance (Hybrid Strategy).

### 📦 Workload Onboard (Service #7)
- [ ] Deploy **Auth Service** (:5006).
- [ ] Update API Gateway: Verify JWT local (Public Key từ Secrets Manager).
- [ ] Chèn RDS Proxy vào giữa ECS Tasks và RDS. Đổi connection string của 6 services cũ.

### 💥 SRE / Chaos Drill
- [ ] **Drill 1 (Auth Down):** Kill Auth Service -> User đang login có gọi được Order không? (Kỳ vọng: CÓ, do API GW cache Public Key).
- [ ] **Drill 2 (Pool Exhaustion):** Dùng k6 bắn 500 concurrent requests -> Quan sát RDS Proxy queue requests, RDS Instance vẫn sống khỏe (Bulkhead Pattern).

### ✅ Definition of Done (DoD)
- [ ] Flow Login -> JWT -> API Gateway -> Order Service.
- [ ] RDS Proxy transparent failover khi bấm nút RDS Multi-AZ Reboot.

---

## ⚙️ PHASE 5: EXPANSION - SAGA & COMPLEX WORKFLOWS
**Mục tiêu:** Làm chủ Distributed Transactions (Saga Pattern) và DLQ.
**Thời gian:** 2.5 Tuần

### 📦 Workload Onboard (Services #8, #9)
- [ ] Deploy **Shipping Service** (:5007) và **Shipping Worker** (:5008 - Saga Orchestrator).
- [ ] Tạo Kafka DLQ topic (`order.shipping.dlq`).

### 💥 SRE / Chaos Drill (The Ultimate Test)
- [ ] **Drill 1 (Zombie Saga):** Kill Shipping Worker khi đang ở state `SHIPPING_PENDING` -> Recovery Job (60s) nhặt lại và resume.
- [ ] **Drill 2 (Compensation):** Inject lỗi 500 vào Shipping Service -> Worker chuyển state `COMPENSATING` -> Gọi refund Payment -> Push DLQ.

### ✅ Definition of Done (DoD)
- [ ] Trace toàn bộ Saga lifecycle trên X-Ray (có `saga_id` attribute).
- [ ] Alert `SagaHighCompensationRate` bắn về Telegram khi tỷ lệ refund > 5%.

---

## 🔍 PHASE 6: EXPANSION - CQRS & SEARCH
**Mục tiêu:** Tách biệt Read/Write Model, xử lý Full-text Search.
**Thời gian:** 1.5 Tuần

### 🧩 Modules triển khai
- [ ] `opensearch` (Module 7): Amazon OpenSearch Service (VPC Access, ISM policies).

### 📦 Workload Onboard (Service #10)
- [ ] Deploy **Search Service** (:5009).
- [ ] Sync data: PostgreSQL -> Kafka -> Search Service -> OpenSearch.

### 💥 SRE / Chaos Drill
- [ ] **Drill 1 (Index Corruption):** Xóa OpenSearch Index -> Search Service fallback về query RDS (Graceful Degradation).
- [ ] **Drill 2 (Zero-Downtime Reindex):** Chạy script reindex từ `orders_v1` sang `orders_v2` -> Switch Alias -> Không rớt request nào.

### ✅ Definition of Done (DoD)
- [ ] Metric `search_index_lag_seconds` < 5s.
- [ ] OpenSearch Down -> Core flow (Order/Payment) không ảnh hưởng.

---

## 🦑 PHASE 7: COMPUTE EVOLUTION & GITOPS (The EKS Era)
**Mục tiêu:** Từ bỏ ECS, chuyển sang EKS (Phase 8C). Thiết lập ranh giới Control Plane / Data Plane.
**Thời gian:** 3 Tuần

### 🧩 Modules triển khai
- [ ] `compute/eks` (Phase 8C): EKS Cluster, Managed Node Groups, IRSA (IAM Roles for Service Accounts).
- [ ] `gitops-bootstrap` (Module 18): ArgoCD, External Secrets Operator (ESO), AWS Load Balancer Controller.

### 📦 Workload Onboard
- [ ] Viết Helm Charts / Kustomize cho 10 Services.
- [ ] ArgoCD App-of-Apps tự động sync từ Git Repo.
- [ ] ESO sync AWS Secrets Manager -> K8s Secrets.

### 💥 SRE / Chaos Drill
- [ ] **Drill 1 (GitOps Self-Healing):** `kubectl delete deployment order-service` -> ArgoCD tự recreate trong < 10s.
- [ ] **Drill 2 (IRSA Magic):** Xóa AWS Credentials trong Pod -> Pod vẫn read được Secrets Manager nhờ IRSA (OIDC).

### ✅ Definition of Done (DoD)
- [ ] Zero-downtime deployment qua ArgoCD Rollouts.
- [ ] Terraform KHÔNG còn quản lý K8s Deployments (chỉ quản lý EKS Cluster).

---

## 🌪️ PHASE 8: DAY-2 OPS & AWS-NATIVE CHAOS (FIS)
**Mục tiêu:** Hạ tầng Production sống ở Day-2. Thực hành Chaos Engineering cấp độ AWS và Upgrade Strategies.
**Thời gian:** 2 Tuần

### 🧩 Modules triển khai
- [ ] `fis` (Module 16): AWS Fault Injection Simulator.
- [ ] `dr` (Module 17): Pilot Light DR (Cross-Region RDS Replica, Route53 Failover).

### 💥 SRE / Chaos Drill (Day-2 Operations)
- [ ] **Drill 1 (EKS Upgrade):** Upgrade EKS 1.29 -> 1.30 (In-place với PDBs) -> Đo thời gian gián đoạn của API Gateway.
- [ ] **Drill 2 (RDS Major Version):** Upgrade PostgreSQL 15 -> 16 (Blue/Green Deployment) -> Verify RDS Proxy transparent failover.
- [ ] **Drill 3 (AWS FIS AZ Failure):** Chạy FIS Experiment tắt toàn bộ EC2 Nodes ở AZ-a -> Quan sát Cluster Autoscaler spin up nodes ở AZ-b/c và ALB route traffic.
- [ ] **Drill 4 (DR Drill):** Route53 Failover Routing sang DR Region -> Đo RTO thực tế.

### ✅ Definition of Done (DoD)
- [ ] Có Runbook cho EKS/RDS Upgrades.
- [ ] FIS Experiment chạy an toàn với Stop Conditions (CloudWatch Alarms).

---

## 📊 Progress Tracker

| Phase | Focus | Services / Modules | Status | Post-Mortem / Learnings |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | Sync Tracer Bullet | Web UI, API GW, Payment, Order (ECS Fargate) | ⚪ Not Started | |
| **Phase 2** | Async Backbone | Cache, Streaming, Notif/Inv Workers | ⚪ Not Started | |
| **Phase 3** | Platform Shield | Bastion, CI/CD (OIDC+OPA), Budgets | ⚪ Not Started | |
| **Phase 4** | Security & Pooling | Auth (#7), RDS Proxy | ⚪ Not Started | |
| **Phase 5** | Saga Workflows | Shipping Svc, Worker (#8, #9) | ⚪ Not Started | |
| **Phase 6** | CQRS & Search | OpenSearch, Search Svc (#10) | ⚪ Not Started | |
| **Phase 7** | EKS & GitOps | EKS, ArgoCD, ESO, AWS LBC | ⚪ Not Started | |
| **Phase 8** | Day-2 Ops & FIS | FIS, DR, EKS/RDS Upgrades | ⚪ Not Started | |