# 🗺️ AWS Reliability Lab — Master Roadmap (Greenfield Workload & Platform Driven)

Tài liệu này là "Kim Chỉ Nam" kết hợp giữa Application Expansion (10 Services) và AWS Terraform Playbook (18 Modules) cho **Greenfield Deployment** (triển khai mới hoàn toàn trên AWS, không phải migration từ On-premises).

**Mục tiêu tối thượng:** Xây dựng một Internal Developer Platform (IDP) thực thụ, nơi hạ tầng sinh ra để phục vụ Workload và tự động hóa việc tuân thủ Compliance.

---

## 📜 4 Nguyên Tắc Bất Di Bất Dịch (The 4 Iron Rules)

1. **No Infra without Workload:** Mọi module hạ tầng mới (RDS Proxy, MSK, ElastiCache) chỉ được build khi có ít nhất 1 Service cần nó.
2. **Chaos is a Feature:** Build xong module nào, phải "phá" (Chaos Drill) module đó ngay (Dùng AWS FIS hoặc thủ công).
3. **OTel-Native Bridge:** Application code chỉ biết push OTLP về `localhost:4317`. Hạ tầng AWS (ADOT Collector Sidecar) sẽ route về AMP (Prometheus), X-Ray, CloudWatch. Tuyệt đối không tự host Loki/Tempo trên AWS để tránh làm "Storage Admin".
4. **Control Plane vs Data Plane Boundary:**
   - **Control Plane** (Terraform — `control-plane/lab/`): VPC, IAM, SGs, RDS, ECR, ECS Cluster, ALB, ACM. (Tốc độ thay đổi: Tuần/Tháng).
   - **Data Plane** (Terraform — `data-plane/`): ECS Service, Task Definition per microservice. Đọc metadata từ Control Plane qua SSM Parameter Store. (Tốc độ thay đổi: Ngày/Giờ).
   - **All-in-One** (`environments/shared/`): Giữ lại làm reference — toàn bộ infra chung 1 state. Phù hợp khi học cách hoạt động trước khi tách.
   - **Future Data Plane** (ArgoCD/GitOps): Khi migrate sang EKS — Deployments, Services, Ingress, HPA.

📌 **Khuyến nghị:** Dùng `control-plane/` + `data-plane/` cho tất cả môi trường mới.

🔥 Xem [`docs/AWS_CHAOS_PLAYBOOK.md`](docs/AWS_CHAOS_PLAYBOOK.md) để kiểm chứng resilience của kiến trúc này (IAM Blackhole, Network Partition).

---

## 🚀 PHASE 1: THE SYNC TRACER BULLET (ECS Fargate) ✅ DONE

**Mục tiêu:** Đưa 2 services cốt lõi (Order, Payment) chạy trên ECS Fargate. Hiểu về AWS Networking, IAM Task Role và ALB.

**Thời gian:** 2 Tuần

### 🧩 Modules triển khai (Playbook)

- [x] `ecr` (Module 9): Lifecycle policy, Image scanning.
- [x] `loadbalancer` (Module 11): ALB Internet-facing, Target Groups.
- [x] `compute/ecs-cluster`: ECS Cluster, Cloud Map namespace.
- [x] `compute/ecs-service`: Task Definition, Service, Circuit Breaker, ECS Exec.
- [x] Control Plane / Data Plane split — SSM Service Catalog integration.

### 📦 Workload Onboard

- [x] Build & Push 2 images (Order, Payment) lên ECR.
- [x] Wire ALB → Order/Payment trực tiếp (chưa có API Gateway).
- [x] Inject `DB_SECRET` từ Secrets Manager vào ECS Task qua IAM Task Role.
  - **Code Wiring:** `order-service/app.py` hàm `_build_database_url()` tự động parse JSON format của AWS Secrets Manager khi biến môi trường `DB_SECRET` được inject.

### 💥 SRE / Chaos Drill

- [x] **Drill 1 (IAM Blackhole):** Revoke Execution Role policy → Circuit Breaker auto-rollback. ✅ Alert wired → `observability.tf`
- [x] **Drill 2 (Network Partition):** Tắt SG Inbound từ ALB → Zombie Task pattern. ✅ Alert wired (Task stopped abnormal)
- [x] **Drill 3 (Poison Config):** Deploy bad image tag / OOM Kill → ExitCode signatures (`null` vs `137` vs `1`). ✅ Alert wired
- [x] **Drill 3.5 (Memory Pressure):** ECS Exec stress → verify `memory-high` alarm leading indicator. ✅ Documented → `AWS_CHAOS_PLAYBOOK.md` Exp 3.5

### ✅ Definition of Done

- [x] Payment service onboard: ✅ DONE
- [x] Order service onboard: ✅ DONE
- [x] Hardening (Iteration A): ✅ DONE — 3 CloudWatch Alarms wired to Telegram
- [x] Time-To-Detect mỗi experiment ≤ 5 phút

### ⚠️ Identified Gaps (to be fixed in Phase 1.5 & 2)

1. **Observability Black Hole:** App đang push OTLP về `otel-collector:4317` (on-prem endpoint) → Chưa có AMP/X-Ray trên AWS.
2. **Missing API Gateway:** Traffic đi thẳng ALB → Order/Payment, chưa test BFF pattern, RFC 7807 propagation.
3. **Container Postgres:** Order service hiện đang connect tới container Postgres trong docker-compose, chưa phải RDS.
4. **Missing SIGTERM Handler:** `order-service/app.py` chưa catch `SIGTERM` để flush Kafka producer khi ECS scale-in/stop task.

---

## 🔭 PHASE 1.5: THE OBSERVABILITY BRIDGE (Greenfield Priority #1) 🆕

**Mục tiêu:** Biến ECS Task từ "mù" thành "sáng" — thiết lập Telemetry Pipeline AWS-native trước khi đưa Stateful Services (RDS/Redis) vào.

**Thời gian:** 0.5 Tuần (3 ngày)

**Rationale:** Trong Greenfield, nếu deploy RDS/ElastiCache mà không có Observability Bridge, khi có lỗi xảy ra (App không connect được RDS, Cache miss storm), bạn sẽ không có Trace để debug. Đây là "Observability Black Hole" cần fix trước khi scale.

### 🧩 Modules triển khai

- [ ] `observability/amp` (Module mới): Tạo Amazon Managed Prometheus workspace.
- [ ] `observability/xray`: Enable X-Ray tracing cho ECS Tasks.
- [ ] Update `compute/ecs-service` module:
  - Thêm **ADOT Collector làm Sidecar Container** trong Task Definition.
  - Inject IAM Task Role với permissions: `aps:RemoteWrite`, `xray:PutTraceSegments`, `logs:PutLogEvents`.
  - Đổi biến môi trường của App: `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` (App chỉ biết push về localhost, Sidecar lo phần còn lại).

### 📦 Workload Wiring

Update Task Definition của Order Service & Payment Service:

```hcl
# ADOT Sidecar Container
{
  name      = "otel-collector"
  image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
  essential = false
  environment = [
    { name = "AOT_CONFIG_CONTENT", value = file("${path.module}/otel-config.yaml") }
  ]
  logConfiguration = {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = "/ecs/otel-sidecar"
      "awslogs-region"        = var.aws_region
      "awslogs-stream-prefix" = "ecs"
    }
  }
}
```

- [ ] Verify traces xuất hiện trên X-Ray Service Map.
- [ ] Verify metrics trên AMP qua Amazon Managed Grafana (AMG) hoặc self-hosted Grafana với AMP datasource.

### 💥 SRE / Chaos Drill

- **Drill 4 (Observability Black Hole):** Kill ADOT sidecar process → App vẫn chạy nhưng trace mất.
  - Kỳ vọng: App không bị crash (OTel SDK có buffer/retry). CloudWatch Alarm `ADOTSidecarDown` bắn.
  - Learning: Hiểu được "Telemetry Pipeline" — thứ mà 90% Junior SRE bỏ qua.

### ✅ Definition of Done

- [ ] X-Ray Service Map hiển thị end-to-end flow: ALB → Order → Payment.
- [ ] AMP workspace nhận metrics từ Order/Payment services.
- [ ] CloudWatch Alarm cho ADOT sidecar health hoạt động.

---

## 🗄️ PHASE 2: THE STATEFUL BOOTSTRAP & ASYNC BACKBONE

**Mục tiêu:** Deploy RDS Multi-AZ + ElastiCache + MSK, và dạy App cách "nhận diện" chúng một cách bảo mật.

**Thời gian:** 2.5 Tuần

**Rationale:** Greenfield không có dữ liệu thật, nên không cần "Dual-write" hay "Read-only phase" như Migration. Thay vào đó, bài toán cốt lõi là Bootstrapping (khởi tạo schema an toàn), Secret Injection (bơm bí mật), và Connection Management (RDS Proxy).

### 🧩 Modules triển khai

- [ ] `database` (Module 4): RDS Multi-AZ + Secrets Manager + KMS.
- [ ] `cache` (Module 5): ElastiCache Redis (Cluster Mode Disabled, Auth Token).
- [ ] `streaming` (Module 6): MSK Kafka (KRaft, 2 brokers).
- [ ] Update `vpc-endpoints`: Thêm RDS, ElastiCache, MSK, Secrets Manager, SSM Endpoints.

### 📦 Workload Onboard & Bootstrap

**2A: The Bootstrap Problem (How to run `init.sql` without Public Accessible)**

- Option 1 (Recommended): Deploy một "Bootstrap Task" chạy image `postgres:alpine` với ECS Exec enabled.

```bash
  # Jump vào task, mount init.sql, chạy psql
  aws ecs execute-command --cluster my-cluster --task <task-id> \
    --container bootstrap --interactive \
    --command "psql -h <rds-endpoint> -U admin -d orders -f /init.sql"
```

- Option 2: Dùng Bastion Host + SSM Session Manager (đã có trong Phase 3 Roadmap gốc, nhưng có thể kéo lên dùng sớm).

Wire `DB_SECRET` ARN từ Secrets Manager vào ECS Task Definition `secrets` block:

```hcl
secrets = [
  {
    name      = "DB_SECRET"
    valueFrom = aws_secretsmanager_secret.rds_credentials.arn
  }
]
```

**2B: Fix SIGTERM Handler (Critical for Kafka Producers)**

Update `order-service/app.py` để catch `SIGTERM` và flush Kafka producer:

```python
import signal

def shutdown_handler(signum, frame):
    logger.info("Received SIGTERM, flushing Kafka producer...")
    if kafka_producer:
        kafka_producer.flush(timeout=5)
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
```

**2C: Deploy Workers**

- [ ] Deploy Notification Worker & Inventory Worker (Kafka Consumers).
- [ ] Wire Redis URL, test Cache-Aside pattern.
- [ ] Wire Kafka bootstrap servers, test event publishing/consuming.

### 💥 SRE / Chaos Drill

- **Drill 5 (RDS Failover):** `aws rds reboot-db-instance --force-failover`
  - Quan sát: X-Ray Trace chỉ ra chính xác bao nhiêu request bị `psycopg2.OperationalError` trong 60s RDS chuyển DNS sang AZ mới.
  - Kỳ vọng: App tự reconnect thành công nhờ `retry_connect()` trong `shared/db_utils.py`.
- **Drill 6 (Cache Miss Storm):** Flush Redis → CloudWatch RDS CPU spike 80%+.
  - Verify: App có circuit breaker cho DB không? Cache-Aside pattern có fallback graceful không?
- **Drill 7 (Secret Rotation):** Rotate Secrets Manager password → App auto-reconnect với new password?
  - Learning: Hiểu được "Secret Rotation Pipeline" của AWS Secrets Manager + Lambda rotation function.
- **Drill 8 (MSK Nightmare):** Kill 1 MSK Broker → Quan sát Partition Leader Election và Consumer Lag.
- **Drill 9 (Graceful Shutdown):** ECS Stop Task Worker → Verify Kafka offset được commit trước khi chết (SIGTERM).

### ✅ Definition of Done

- [ ] End-to-end flow: User mua hàng → Order → Kafka → Workers → DB.
- [ ] RDS Multi-AZ failover transparent với app (nhờ `retry_connect`).
- [ ] Verify RDS/Redis/MSK traffic KHÔNG đi qua NAT Gateway (dùng VPC Flow Logs + Athena).
- [ ] Kafka producer flush thành công khi ECS scale-in/stop task.

---

## 🌐 PHASE 2.5: THE API GATEWAY COMPLETION 🆕

**Mục tiêu:** Hoàn thiện entry point, test real user flow với BFF pattern.

**Thời gian:** 1 Tuần

### 📦 Workload Onboard

- [ ] Deploy API Gateway service (Phase 5 code đã sẵn sàng).
- [ ] Wire ALB → API GW → Order/Payment.
- [ ] Enable traffic tagging (synthetic vs organic) trong API GW.
- [ ] Test RFC 7807 error propagation từ Payment → Order → API GW → Client.

### 💥 SRE / Chaos Drill

- **Drill 10 (Gateway Timeout):** Inject 6s delay vào Payment → API GW trả 504.
- **Drill 11 (BFF Aggregation Failure):** Kill Order Service → API GW trả 502 + RFC 7807.
- **Drill 12 (Traffic Source Analysis):** Verify synthetic traffic bị exclude khỏi SLO calculation.

### ✅ Definition of Done

- [ ] Web UI có thể tạo order qua API Gateway.
- [ ] RFC 7807 errors được propagate đúng cách.
- [ ] Synthetic traffic không inflate SLO burn rate.

---

## 🛡️ PHASE 3: THE PLATFORM SHIELD & PR-DRIVEN IaC

**Mục tiêu:** Chuyển dịch từ "ClickOps/Local Apply" sang PR-Driven Infrastructure. Bảo vệ hạ tầng trước khi scale.

**Thời gian:** 1.5 Tuần

### 🧩 Modules triển khai

- [ ] `bastion` (Module 12): EC2 + SSM Session Manager (No SSH).
- [ ] `cicd` (Module 13): OIDC Provider, GitHub Actions IAM Roles (Plan vs Apply).
- [ ] `budgets` (Module 15): AWS Budgets + Cost Anomaly Detection.

### 📦 Platform Onboard

- [ ] **Shift-Left:** Chặn `terraform apply` local. Bắt buộc push code → GHA Plan → OPA Conftest Scan → PR Comment → Merge → Apply.
- [ ] Dùng SSM Session Manager qua Bastion để nhảy vào RDS/MSK debug (thay vì mở port 5432 ra Internet).

⏸️ **Sprint A.3 từ Iteration A** (deferred tới đây): Sau khi OIDC + GHA pipeline sẵn sàng, implement:

- OPA Rego policy chặn PR Terraform xóa `AmazonECSTaskExecutionRolePolicy` khỏi ECS Task Execution Role.
- CI/CD pre-deploy gate: `aws ecr describe-images --image-ids imageTag=$TAG` validate image tồn tại trước deploy.

Tools cần học trước: `Conftest` · `tfsec` · `Checkov`

### 💥 SRE / Chaos Drill

- **Drill 13 (OPA Block):** Cố tình mở port 22 trên Security Group trong PR → OPA block PR.
- **Drill 14 (FinOps Alert):** Bật Flow Logs ALL traffic + 3 NAT Gateways → Chờ AWS Budgets bắn alert email.

### ✅ Definition of Done

- [ ] 100% infra changes đi qua PR và OPA scan.
- [ ] Connect thành công vào RDS từ Bastion qua SSM (không dùng SSH key).

---

## 🔐 PHASE 4: EXPANSION — SECURITY & CONNECTION POOLING

**Mục tiêu:** Onboard Auth Service và giải quyết bẫy "Connection Exhaustion" trước khi thêm 4 services nữa.

**Thời gian:** 2 Tuần

### ⚠️ Connection Exhaustion Math (from code review)

- `DB_POOL_MAX = 10` per ECS Task (in `order-service/app.py`)
- Phase 1: 2 services × 1 task × 10 conn = **20 connections** → OK
- Phase 4: 10 services × 1 task × 10 conn = **100 connections** → RDS `db.t3.micro` limit (~150) → danger zone
- Scaling: 10 services × 3 tasks × 10 conn = **300 connections** → RDS Proxy bắt buộc

### 🧩 Modules triển khai

- [ ] `rds-proxy` (Module 8): RDS Proxy (Transaction mode, IAM Auth). So sánh thực tế với self-hosted PgBouncer.
- [ ] Update `database`: Tạo thêm `auth_db` và `shipping_db` trên cùng RDS Instance (Hybrid Strategy).

### 📦 Workload Onboard (Service #7)

- [ ] Deploy Auth Service (`:5006`).
- [ ] Update API Gateway: Verify JWT local (Public Key từ Secrets Manager).
- [ ] Chèn RDS Proxy vào giữa ECS Tasks và RDS. Đổi connection string của 6 services cũ.

### 💥 SRE / Chaos Drill

- **Drill 15 (Auth Down):** Kill Auth Service → User đang login có gọi được Order không? (Kỳ vọng: CÓ, do API GW cache Public Key).
- **Drill 16 (Pool Exhaustion):** Dùng k6 bắn 500 concurrent requests → Quan sát RDS Proxy queue requests, RDS Instance vẫn sống khỏe (Bulkhead Pattern).

### 🔀 Decision Gate: Cloud Map DNS → ECS Service Connect

Tại Phase 4, hệ thống sẽ có 5+ services gọi nhau. Đây là thời điểm evaluate migrate từ Cloud Map DNS sang ECS Service Connect.

**Criteria để migrate:**

- Zombie Task blind spot (Exp 2, 6) đã confirm là risk thực tế
- Cascading failure (Exp 5) cần Envoy retry/outlier detection
- Cần HTTP error rate metrics từ Envoy (thay vì build custom)

📖 Chi tiết concept + Terraform config: `docs/ECS_SERVICE_CONNECT.md`

### ✅ Definition of Done

- [ ] Flow Login → JWT → API Gateway → Order Service.
- [ ] RDS Proxy transparent failover khi bấm nút RDS Multi-AZ Reboot.
- [ ] Decision: Cloud Map DNS vs Service Connect — documented in ADR.

---

## ⚙️ PHASE 5: EXPANSION — SAGA & COMPLEX WORKFLOWS

**Mục tiêu:** Làm chủ Distributed Transactions (Saga Pattern) và DLQ.

**Thời gian:** 2.5 Tuần

### 📦 Workload Onboard (Services #8, #9)

- [ ] Deploy Shipping Service (`:5007`) và Shipping Worker (`:5008` — Saga Orchestrator).
- [ ] Tạo Kafka DLQ topic (`order.shipping.dlq`).

### 💥 SRE / Chaos Drill (The Ultimate Test)

- **Drill 17 (Zombie Saga):** Kill Shipping Worker khi đang ở state `SHIPPING_PENDING` → Recovery Job (60s) nhặt lại và resume.
- **Drill 18 (Compensation):** Inject lỗi 500 vào Shipping Service → Worker chuyển state `COMPENSATING` → Gọi refund Payment → Push DLQ.

### ✅ Definition of Done

- [ ] Trace toàn bộ Saga lifecycle trên X-Ray (có `saga_id` attribute).
- [ ] Alert `SagaHighCompensationRate` bắn về Telegram khi tỷ lệ refund > 5%.

---

## 🔍 PHASE 6: EXPANSION — CQRS & SEARCH

**Mục tiêu:** Tách biệt Read/Write Model, xử lý Full-text Search.

**Thời gian:** 1.5 Tuần

### 🧩 Modules triển khai

- [ ] `opensearch` (Module 7): Amazon OpenSearch Service (VPC Access, ISM policies).

### 📦 Workload Onboard (Service #10)

- [ ] Deploy Search Service (`:5009`).
- [ ] Sync data: PostgreSQL → Kafka → Search Service → OpenSearch.

### 💥 SRE / Chaos Drill

- **Drill 19 (Index Corruption):** Xóa OpenSearch Index → Search Service fallback về query RDS (Graceful Degradation).
- **Drill 20 (Zero-Downtime Reindex):** Chạy script reindex từ `orders_v1` sang `orders_v2` → Switch Alias → Không rớt request nào.

### ✅ Definition of Done

- [ ] Metric `search_index_lag_seconds` < 5s.
- [ ] OpenSearch Down → Core flow (Order/Payment) không ảnh hưởng.

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
- [ ] ESO sync AWS Secrets Manager → K8s Secrets.

### 💥 SRE / Chaos Drill

- **Drill 21 (GitOps Self-Healing):** `kubectl delete deployment order-service` → ArgoCD tự recreate trong < 10s.
- **Drill 22 (IRSA Magic):** Xóa AWS Credentials trong Pod → Pod vẫn read được Secrets Manager nhờ IRSA (OIDC).

### ✅ Definition of Done

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

- **Drill 23 (EKS Upgrade):** Upgrade EKS 1.29 → 1.30 (In-place với PDBs) → Đo thời gian gián đoạn của API Gateway.
- **Drill 24 (RDS Major Version):** Upgrade PostgreSQL 15 → 16 (Blue/Green Deployment) → Verify RDS Proxy transparent failover.
- **Drill 25 (AWS FIS AZ Failure):** Chạy FIS Experiment tắt toàn bộ EC2 Nodes ở AZ-a → Quan sát Cluster Autoscaler spin up nodes ở AZ-b/c và ALB route traffic.
- **Drill 26 (DR Drill):** Route53 Failover Routing sang DR Region → Đo RTO thực tế.

### ✅ Definition of Done

- [ ] Có Runbook cho EKS/RDS Upgrades.
- [ ] FIS Experiment chạy an toàn với Stop Conditions (CloudWatch Alarms).

---

## 📊 Progress Tracker

| Phase | Focus | Services / Modules | Status | Post-Mortem / Learnings |
|-------|-------|-------------------|--------|------------------------|
| Phase 1 | Sync Tracer Bullet | Order, Payment (ECS Fargate) | ✅ DONE | Chaos Drills 1-3.5 done. Identified gaps: Observability, API GW, SIGTERM handler |
| Phase 1.5 🆕 | Observability Bridge | AMP, X-Ray, ADOT Sidecar | ⚪ Not Started | |
| Phase 2 | Stateful Bootstrap | RDS, ElastiCache, MSK, Workers | ⚪ Not Started | |
| Phase 2.5 🆕 | API Gateway Completion | API Gateway service | ⚪ Not Started | |
| Phase 3 | Platform Shield | Bastion, CI/CD (OIDC+OPA), Budgets | ⚪ Not Started | |
| Phase 4 | Security & Pooling | Auth (#7), RDS Proxy | ⚪ Not Started | |
| Phase 5 | Saga Workflows | Shipping Svc, Worker (#8, #9) | ⚪ Not Started | |
| Phase 6 | CQRS & Search | OpenSearch, Search Svc (#10) | ⚪ Not Started | |
| Phase 7 | EKS & GitOps | EKS, ArgoCD, ESO, AWS LBC | ⚪ Not Started | |
| Phase 8 | Day-2 Ops & FIS | FIS, DR, EKS/RDS Upgrades | ⚪ Not Started | |