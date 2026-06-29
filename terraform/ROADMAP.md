# 🗺️ AWS Reliability Lab - Master Roadmap (Workload & Platform Driven)

Tài liệu này là "Kim Chỉ Nam" kết hợp giữa **Application Expansion** (10 Services) và **AWS Terraform Playbook** (18 Modules). 
Mục tiêu tối thượng: Xây dựng một Internal Developer Platform (IDP) thực thụ, nơi hạ tầng sinh ra để phục vụ Workload và tự động hóa việc tuân thủ Compliance.

## 📜 4 Nguyên Tắc Bất Di Bất Dịch (The 4 Iron Rules)
1. **No Infra without Workload:** Mọi module hạ tầng mới (RDS Proxy, MSK, ElastiCache) chỉ được build khi có ít nhất 1 Service cần nó.
2. **Chaos is a Feature:** Build xong module nào, phải "phá" (Chaos Drill) module đó ngay (Dùng AWS FIS hoặc thủ công).
3. **OTel-Native Bridge:** Application code chỉ biết push OTLP. Hạ tầng AWS (ADOT Collector) sẽ route về AMP (Prometheus), X-Ray, CloudWatch. **Tuyệt đối không tự host Loki/Tempo trên AWS** để tránh làm "Storage Admin".
4. **Control Plane vs Data Plane Boundary:** 
   - *Control Plane (Terraform — `control-plane/lab/`):* VPC, IAM, SGs, RDS, ECR, ECS Cluster, ALB, ACM. (Tốc độ thay đổi: Tuần/Tháng).
   - *Data Plane (Terraform — `data-plane/`):* ECS Service, Task Definition per microservice. Đọc metadata từ Control Plane qua SSM Parameter Store. (Tốc độ thay đổi: Ngày/Giờ).
   - *All-in-One (`environments/shared/`):* Giữ lại làm **reference** — toàn bộ infra chung 1 state. Phù hợp khi học cách hoạt động trước khi tách.
   - *Future Data Plane (ArgoCD/GitOps):* Khi migrate sang EKS — Deployments, Services, Ingress, HPA.
   - 📌 **Khuyến nghị:** Dùng `control-plane/` + `data-plane/` cho tất cả môi trường mới.
   - 🔥 Xem [`docs/AWS_CHAOS_PLAYBOOK.md`](docs/AWS_CHAOS_PLAYBOOK.md) để kiểm chứng resilience của kiến trúc này (IAM Blackhole, Network Partition).

---

## 🚀 PHASE 1: THE SYNC TRACER BULLET (ECS Fargate)
**Mục tiêu:** Đưa 4 services cốt lõi (Web UI, API GW, Order, Payment) chạy trên ECS Fargate. Hiểu về AWS Networking, IAM Task Role và ALB.
**Thời gian:** 2 Tuần

### 🧩 Modules triển khai (Playbook)
- [ ] `ecr` (Module 9): Lifecycle policy, Image scanning.
- [ ] `loadbalancer` (Module 11): ALB Internet-facing, Target Groups, ACM (DNS validation).
- [ ] `compute/ecs-fargate` (Phase 8B): ECS Cluster, Task Definitions.
- [ ] `compute/ecs-cluster`: ECS Cluster, Cloud Map namespace.
- [ ] `compute/ecs-service`: Task Definition, Service, Circuit Breaker, ECS Exec.
- [ ] *Control Plane / Data Plane split* — SSM Service Catalog integration.

### 📦 Workload Onboard
- [ ] Build & Push 4 images lên ECR.
- [ ] Wire ALB -> API Gateway -> Order/Payment.
- [ ] Inject `DATABASE_URL` từ Secrets Manager vào ECS Task qua IAM Task Role.

### 💥 SRE / Chaos Drill
- [x] **Drill 1 (IAM Blackhole):** Revoke Execution Role policy -> Circuit Breaker auto-rollback. ✅ Alert wired → `observability.tf`
- [x] **Drill 2 (Network Partition):** Tắt SG Inbound từ ALB -> Zombie Task pattern. ✅ Alert wired (Task stopped abnormal)
- [x] **Drill 3 (Poison Config):** Deploy bad image tag / OOM Kill -> ExitCode signatures (`null` vs `137` vs `1`). ✅ Alert wired
- [x] **Drill 3.5 (Memory Pressure):** ECS Exec stress → verify `memory-high` alarm leading indicator. ✅ Documented → `AWS_CHAOS_PLAYBOOK.md` Exp 3.5

> 📖 Chi tiết tất cả drills: [`docs/AWS_CHAOS_PLAYBOOK.md`](docs/AWS_CHAOS_PLAYBOOK.md)

### ✅ Definition of Done — Hardening (Iteration A)

> Tick sau khi chạy `terraform apply` và re-run 3 experiments với alerting.

- [ ] Telegram bot nhận đủ alert từ 3 lần re-run Experiment (screenshot vào notebook).
- [ ] Time-To-Detect mỗi experiment ≤ 5 phút (ghi TTD vào notebook).
- [ ] 3 CloudWatch Alarm (memory-high, cpu-high, running-task-low) ở state `OK` (không `INSUFFICIENT_DATA`).
- [ ] Stress test (Exp 3.5) gây alarm Memory fire trong < 3 phút + Telegram nhận đủ 2 tin (ALARM + OK).
- [ ] Toàn bộ infra mới qua Terraform, không có ClickOps.
- [ ] Cập nhật dòng dưới: **`payment-service` onboard: ✅ DONE, Hardening: ✅ DONE**

### ✅ Definition of Done (DoD) — Phase 1 gốc
- [ ] `curl https://<ALB_DNS>/health/live` trả về 200 OK.
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

> ⚠️ **Code review finding:** `order-service/app.py` hiện KHÔNG catch `SIGTERM` → Kafka `flush(timeout=2)` chỉ chạy trong request handler, không chạy khi ECS kill task. Phase 2 phải implement `signal.signal(SIGTERM, shutdown_handler)` cho tất cả Kafka producers/consumers.

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

> ⏸️ **Sprint A.3 từ Iteration A (deferred tới đây):** Sau khi OIDC + GHA pipeline sẵn sàng, implement:
> 1. OPA Rego policy chặn PR Terraform xóa `AmazonECSTaskExecutionRolePolicy` khỏi ECS Task Execution Role.
> 2. CI/CD pre-deploy gate: `aws ecr describe-images --image-ids imageTag=$TAG` validate image tồn tại trước deploy.
>
> Tools cần học trước: [Conftest](https://www.conftest.dev/) · [tfsec](https://github.com/aquasecurity/tfsec) · [Checkov](https://www.checkov.io/)

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

> ⚠️ **Connection Exhaustion Math (from code review):**
> - `DB_POOL_MAX = 10` per ECS Task (in `order-service/app.py`)
> - Phase 1: 2 services × 1 task × 10 conn = **20 connections** → OK
> - Phase 4: 10 services × 1 task × 10 conn = **100 connections** → RDS `db.t3.micro` limit (~150) → **danger zone**
> - Scaling: 10 services × 3 tasks × 10 conn = **300 connections** → **RDS Proxy bắt buộc**

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

### 🔀 Decision Gate: Cloud Map DNS → ECS Service Connect
> Tại Phase 4, hệ thống sẽ có **5+ services** gọi nhau. Đây là thời điểm evaluate migrate từ Cloud Map DNS sang ECS Service Connect.
>
> **Criteria để migrate:**
> - [ ] Zombie Task blind spot (Exp 2, 6) đã confirm là risk thực tế
> - [ ] Cascading failure (Exp 5) cần Envoy retry/outlier detection
> - [ ] Cần HTTP error rate metrics từ Envoy (thay vì build custom)
>
> 📖 Chi tiết concept + Terraform config: [`docs/ECS_SERVICE_CONNECT.md`](docs/ECS_SERVICE_CONNECT.md)

### ✅ Definition of Done (DoD)
- [ ] Flow Login -> JWT -> API Gateway -> Order Service.
- [ ] RDS Proxy transparent failover khi bấm nút RDS Multi-AZ Reboot.
- [ ] **Decision:** Cloud Map DNS vs Service Connect — documented in ADR.

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
| **Phase 1** | Sync Tracer Bullet | Web UI, API GW, Payment, Order (ECS Fargate) | 🟡 In Progress (Payment ✅, Order ✅, API GW ⚪, Web UI ⚪) | Chaos Drills 1-3.5 done. Cloud Map blind spot discovered. |
| **Phase 2** | Async Backbone | Cache, Streaming, Notif/Inv Workers | ⚪ Not Started | |
| **Phase 3** | Platform Shield | Bastion, CI/CD (OIDC+OPA), Budgets | ⚪ Not Started | |
| **Phase 4** | Security & Pooling | Auth (#7), RDS Proxy | ⚪ Not Started | |
| **Phase 5** | Saga Workflows | Shipping Svc, Worker (#8, #9) | ⚪ Not Started | |
| **Phase 6** | CQRS & Search | OpenSearch, Search Svc (#10) | ⚪ Not Started | |
| **Phase 7** | EKS & GitOps | EKS, ArgoCD, ESO, AWS LBC | ⚪ Not Started | |
| **Phase 8** | Day-2 Ops & FIS | FIS, DR, EKS/RDS Upgrades | ⚪ Not Started | |