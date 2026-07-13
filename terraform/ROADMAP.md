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
## 🎯 Pod Deployment Philosophy (NEW STRATEGY)

Thay vì onboard tuần tự từng service (anti-pattern cho distributed systems), chúng ta deploy theo **Functional Pods** — mỗi Pod là một hệ sinh thái hoàn chỉnh, có thể chạy Chaos Test ngay lập tức.

### Tại sao KHÔNG onboard rời rạc?

| Vấn đề | Sequential (cũ) | Pod Deployment (mới) |
|---|---|---|
| Chaos Drills | Chỉ test 1 service cô lập → không phát hiện cascading failure | Test full data flow → phát hiện "chết chùm" |
| Observability | X-Ray trace cụt: `ALB → Order → DB` | X-Ray trace đầy đủ: `Web UI → API GW → Order → Payment → Kafka → Workers → DB` |
| Learning value | Học được 1 service | Học được distributed systems patterns |
| Time-to-value | 6 tuần mới có hệ thống test được | 2 tuần đã có full functional unit |

### 3 Pods chính của dự án

| Pod | Tuần | Thành phần | Mục tiêu học |
|-----|------|------------|--------------|
| **POD 1: The Illumination** | 1-2 | Order + Payment + AMP + AMG + X-Ray | "Nhìn thấy" được hệ thống qua telemetry |
| **POD 2: The Critical Path** | 3-5 | RDS + ElastiCache + MSK + 6 services đồng loạt | Full distributed flow end-to-end |
| **POD 3: The Chaos Dojo** | 6-10 | AWS FIS + Chaos Drills production-grade | Self-healing validation + incident response |

### Nguyên tắc "Pod Completeness"

Mỗi Pod PHẢI đạt được **3 tiêu chí** trước khi chuyển Pod tiếp theo:

1. **Observable**: Có ít nhất 1 X-Ray trace xuyên suốt toàn bộ Pod
2. **Testable**: Có Traffic Generator hoặc synthetic test chạy được
3. **Breakable**: Có ít nhất 1 Chaos Drill chứng minh Pod tự phục hồi


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

## 🔭 PHASE 1.5: THE ILLUMINATION (POD 1 — Observability Bridge) 🆕

**Mục tiêu:** Biến ECS Task từ "mù" thành "sáng" — thiết lập Telemetry Pipeline AWS-native trước khi đưa Stateful Services (RDS/Redis) vào.

**Thời gian:** 0.5 Tuần (3 ngày)

**Rationale:** Trong Greenfield, nếu deploy RDS/ElastiCache mà không có Observability Bridge, khi có lỗi xảy ra (App không connect được RDS, Cache miss storm), bạn sẽ không có Trace để debug. Đây là "Observability Black Hole" cần fix trước khi scale.

### 🧩 Modules triển khai

- [ ] `observability/amp` (Module mới): Tạo Amazon Managed Prometheus workspace.
- [ ] `observability/xray`: Enable X-Ray tracing cho ECS Tasks.
- [ ] `observability/amg` (Module mới): Tạo Amazon Managed Grafana workspace.
  - Authentication: AWS IAM Identity Center (SSO) hoặc SAML
  - Data sources: AMP workspace + X-Ray
  - Dashboard as Code: JSON provisioned từ Git (Phase 3 sẽ áp dụng)
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
- [ ] **Setup Amazon Managed Grafana (AMG):**
  - Tạo AMG workspace qua Terraform (`aws_grafana_workspace`)
  - Configure AWS IAM Identity Center làm identity provider (SSO)
  - Add AMP workspace làm Prometheus data source (SigV4 auth)
  - Add X-Ray làm data source
  - Import JSON dashboard từ `on-premises/observability-vm/grafana/dashboards/Application/`
- [ ] Verify traces xuất hiện trên X-Ray Service Map.
- [ ] Verify metrics trên AMP hiển thị đúng trên AMG dashboard.
- [ ] Create 1 custom dashboard: "POD 1 — The Illumination" với 4 panels:
  - P95 latency (Order + Payment)
  - Error rate (by HTTP status code)
  - Request rate (by traffic_source)
  - DB pool wait duration

### 🎯 POD 1 Definition of Done

- [ ] **Observable**: X-Ray Service Map hiện rõ `Order → Payment → RDS` với latency breakdown
- [ ] **Queryable**: AMP có ít nhất 5 metrics: `http_server_duration`, `http_server_request_count`, `db_pool_wait_duration_seconds`, `payment_gateway_duration_seconds`, `orders_created_total`
- [ ] **Dashboardable**: AMG workspace deployed và accessible qua SSO
- [ ] **Dashboardable**: AMP + X-Ray data sources connected thành công
- [ ] **Dashboardable**: 1 custom dashboard "POD 1 — The Illumination" với 4 panels hiển thị real-time data
- [ ] **Testable**: Python E2E script bắn 100 requests → verify 100 traces trên X-Ray

💥 SRE / Chaos Drill (The "Who Watches the Watchmen?" Series)
- [x] Drill 7 (Trace Storm): Spam 50k spans → Verify `memory_limiter` backpressure & Tail-based sampling.
- [x] Drill 8 (Silent Blinder): Revoke AMP IAM → Verify Partial Failure & Meta-monitoring via Self-Metrics.
- [x] Drill 9 (Cardinality Bomb): Inject UUID labels → Verify FinOps Guardrails & Label Sanitization.
- [x] Drill 10 (Zombie Sidecar): Kill ADOT process → Verify App-level Watchdog (Suicide Pattern) vs Essential=true trade-off.

### ✅ Definition of Done

- [x] X-Ray Service Map & AMP metrics flowing.
- [x] ADOT `memory_limiter` and `tail_sampling` processors configured and tested.
- [x] Meta-monitoring established: CloudWatch Alarms for ADOT Self-Metrics (`exporter_send_failed`) & AMP `ActiveSeries`.
- [x] ADR written: "Observability Sidecar Lifecycle: essential=false + App Watchdog vs essential=true".

---

## 🗄️ PHASE 2: THE CRITICAL PATH (POD 2 — Full Distributed System)

**Mục tiêu:** Deploy ĐỒNG LOẠT toàn bộ trục xương sống của E-commerce — không onboard rời rạc.
**Thời gian:** 3 tuần
**Rationale:** 6 services này tạo thành 1 functional unit không thể tách rời. Deploy cùng lúc để test được cascading failure, event-driven patterns, và full X-Ray trace.

### 🧩 Modules triển khai (Deploy cùng lúc)

- [ ] `database` (Module 4): RDS Multi-AZ + Secrets Manager + KMS
- [ ] `cache` (Module 5): ElastiCache Redis (Cluster Mode Disabled, Auth Token)
- [ ] `streaming` (Module 6): MSK Kafka (KRaft, 2 brokers)
- [ ] Update `vpc-endpoints`: Thêm RDS, ElastiCache, MSK, Secrets Manager, SSM Endpoints

### 📦 Workload Onboard ĐỒNG LOẠT (6 services cùng lúc)

**Backend Services:**

- [ ] Order Service (`:5001`) — PostgreSQL + Redis + Kafka producer
- [ ] Payment Service (`:5002`) — Redis idempotency + Circuit Breaker
- [ ] API Gateway (`:5000`) — BFF pattern, RFC 7807 propagation
- [ ] Web UI (`:8580`) — Frontend với traffic tagging

**Async Workers:**

- [ ] Notification Worker (`:5004`) — Kafka consumer, idempotent
- [ ] Inventory Worker (`:5005`) — Kafka consumer, pessimistic locking

**Traffic Source:**

- [ ] Traffic Generator (`:5003`) — Synthetic load testing

### 2A: The Bootstrap Problem (How to run `init.sql` without Public Accessible)

**Option 1 (Recommended):** Deploy một "Bootstrap Task" chạy image `postgres:alpine` với ECS Exec enabled.

```bash
aws ecs execute-command --cluster my-cluster --task <task-id> \
  --container bootstrap --interactive \
  --command "psql -h <rds-endpoint> -U admin -d orders -f /init.sql"
```

**Option 2:** Dùng Bastion Host + SSM Session Manager (kéo từ Phase 3 lên dùng sớm).

### 2B: Wire Secrets & Environment Variables

```hcl
secrets = [
  {
    name      = "DB_SECRET"
    valueFrom = aws_secretsmanager_secret.rds_credentials.arn
  }
]

environment = {
  DB_HOST                 = data.aws_ssm_parameter.db_host.value
  DB_PORT                 = data.aws_ssm_parameter.db_port.value
  DB_NAME                 = data.aws_ssm_parameter.db_name.value
  REDIS_URL               = "redis://${module.elasticache.endpoint}:6379"
  KAFKA_BOOTSTRAP_SERVERS = module.msk.bootstrap_brokers
  ENABLE_REDIS            = "true"   # ← BẬT LẠI (was false in Phase 1)
  ENABLE_KAFKA            = "true"   # ← BẬT LẠI (was false in Phase 1)
}
```

### 2C: Verify End-to-End Flow

```
User → Web UI → API GW → Order → Payment (sync)
                        ↓
                      Kafka → Workers (async)
                        ↓
                      RDS + Redis (state)
```

### 💥 SRE / Chaos Drills (POD 2 — Stateful Chaos)

| # | Drill | Blast Radius | Skill học được |
|---|-------|--------------|-----------------|
| 11 | The DB Earthquake (RDS Multi-AZ Failover) | RDS + Order + Payment | `aws rds reboot-db-instance --force-failover`, `psycopg2` retry logic |
| 12 | The Cache Avalanche (Redis Flush) | ElastiCache + Order Service | Cache miss storm, DB connection pool saturation |
| 13 | The Kafka Partition (MSK Broker Loss) | MSK + Workers | Partition leader election, consumer group rebalance |
| 14 | The Zombie Consumer (Stop Worker) | Notification/Inventory Worker | Consumer lag detection, offset commit behavior |
| 15 | The Graceful Guillotine (ECS Stop Task) | 1 ECS Task | SIGTERM handling, Kafka buffer flush, DB pool close |

### ✅ POD 2 Definition of Done

- [ ] **Observable:** 1 full X-Ray trace: Web UI → ALB → API GW → Order → Payment → RDS + Kafka event flow visible
- [ ] **Resilient:** RDS Multi-AZ failover transparent với app (nhờ `retry_connect`)
- [ ] **Efficient:** Verify RDS/Redis/MSK traffic KHÔNG đi qua NAT Gateway (dùng VPC Flow Logs + Athena)
- [ ] **Graceful:** Kafka producer flush thành công khi ECS scale-in/stop task
- [ ] **Testable:** Web UI có thể tạo order → thấy notification trong Notification Worker → thấy stock giảm trong Inventory Worker

## 🌪️ PHASE 2.7: THE AWS CHAOS DOJO (POD 3 — Production-Grade Chaos) 🆕

**Mục tiêu:** "Phá" toàn bộ POD 2 để validate production-grade patterns. Chuyển từ "Chaos thủ công" sang "AWS-native Chaos Engineering" với FIS.
**Thời gian:** 4 tuần
**Rationale:** Đây là phần missing lớn nhất trong ROADMAP hiện tại. Chaos Engineering trên AWS KHÔNG phải là `docker stop container` — mà là nghệ thuật tấn công vào Control Plane và Fault Domains.

### 🎯 Pod-based Chaos Philosophy

Trong production, sự cố KHÔNG BAO GIỜ xảy ra ở 1 layer duy nhất:
- RDS failover → Connection pool exhaustion → Order service timeout → API GW 504 → User retry storm
- MSK broker die → Consumer lag → Notification delay → Customer complain → Support overload

**3 Quy tắc mới cho mọi experiment từ POD 3:**

1. **Always inject at the infrastructure layer, observe at ALL layers**
   - Inject: RDS failover (AWS API)
   - Observe: ECS task → App logs → Kafka consumer lag → Web UI error rate → Telegram alerts

2. **Measure the "User Pain Score"**
   - Không chỉ "service có chết không?" mà là "user có nhận thấy không?"
   - Metric: % successful orders trong thời gian chaos

3. **Blast Radius = 1 Pod, không phải 1 Service**
   - Khi test RDS failover, PHẢI có Traffic Generator đang chạy
   - Khi test MSK broker loss, PHẢI có cả 2 Workers đang consume

### 🧩 Modules triển khai

- [ ] `fis` (Module 16): AWS Fault Injection Simulator — vũ khí tối thượng của SRE
- [ ] `dr` (Module 17): Pilot Light DR (Cross-Region RDS Replica, Route53 Failover)

### 💥 Chaos Experiments (POD 3 — Full-Stack Chaos với AWS FIS)

| # | Experiment | Blast Radius | Skill học được |
|---|---|---|---|
| 16 | **The AZ Apocalypse** (AWS FIS) | Toàn bộ resources trong 1 AZ | Multi-AZ resilience, ALB cross-zone routing |
| 17 | **The Cascade Symphony** (Full-stack) | Web UI → API GW → Order → Payment → DB | End-to-end SLO impact, RFC 7807 propagation |
| 18 | **The Secret Betrayal** (Secrets Manager Rotation) | RDS + all services | Auto-reconnect with new password, zero-downtime rotation |
| 19 | **The Kafka Earthquake** (MSK Broker Loss) | MSK + Workers | Partition leader election, consumer lag detection |
| 20 | **The Cache Apocalypse** (ElastiCache Node Failure) | Redis + Order + Payment | Cache miss storm, DB connection pool exhaustion |
| 21 | **The Graceful Guillotine 2.0** (ECS Rolling Update) | All services | SIGTERM handling, zero-downtime deployment |

### 📊 Mỗi experiment PHẢI có:

1. **Pre-flight checklist** (verify cả POD healthy, không chỉ 1 service)
2. **3+ terminals parallel observation** (infra + app + user perspective)
3. **User Pain Score measurement** (% successful orders during chaos)
4. **X-Ray trace analysis** (show latency breakdown trước/sau chaos)
5. **Post-mortem template** điền sẵn 5 Whys

### ✅ POD 3 Definition of Done

- [ ] **Automated**: Mỗi experiment có AWS FIS Experiment Template (Terraform)
- [ ] **Observable**: Mỗi experiment có Grafana dashboard visualize impact
- [ ] **Documented**: Mỗi experiment có post-mortem viết theo template
- [ ] **Alerted**: Telegram alerts fire đúng với severity expected
- [ ] **Fast**: TTD (Time-To-Detect) ≤ 3 phút cho mọi SEV-2 incidents
- [ ] **Self-healing**: Hệ thống tự phục hồi mà không cần human intervention

### 🎓 Skills đạt được sau POD 3

Sau khi hoàn thành POD 3, bạn sẽ:

| Skill | Level | Ứng dụng thực tế |
|---|---|---|
| AWS FIS | Advanced | Design chaos experiments an toàn cho production |
| Multi-AZ Architecture | Expert | Build systems survive AZ failures |
| Incident Response | Senior | Triage + resolve SEV-2 incidents trong < 30 phút |
| Post-Mortem Writing | Senior | Write blameless post-mortems impress interviewer |
| SLO/SLI Design | Expert | Define meaningful SLOs cho distributed systems |
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

| Phase | Pod | Focus | Services / Modules | Status | Post-Mortem / Learnings |
|-------|-----|-------|-------------------|--------|------------------------|
| Phase 1 | — | Sync Tracer Bullet | Order, Payment (ECS Fargate) | ✅ DONE | Chaos Drills 1-3.5 done. Identified gaps: Observability, API GW, SIGTERM handler |
| Phase 1.5 | **POD 1** | The Illumination | AMP, X-Ray, ADOT Sidecar | ⚪ Not Started | **Mục tiêu:** "Nhìn thấy" được hệ thống qua telemetry |
| Phase 2 | **POD 2** | The Critical Path | RDS, ElastiCache, MSK, 6 services đồng loạt | ⚪ Not Started | **Mục tiêu:** Full distributed flow end-to-end |
| Phase 2.7 🆕 | **POD 3** | The Chaos Dojo | AWS FIS, DR, Full-stack Chaos Drills | ⚪ Not Started | **Mục tiêu:** Self-healing validation + incident response |
| Phase 3 | — | Platform Shield | Bastion, CI/CD (OIDC+OPA), Budgets | ⚪ Not Started | |
| Phase 4 | — | Security & Pooling | Auth (#7), RDS Proxy | ⚪ Not Started | |
| Phase 5 | — | Saga Workflows | Shipping Svc, Worker (#8, #9) | ⚪ Not Started | |
| Phase 6 | — | CQRS & Search | OpenSearch, Search Svc (#10) | ⚪ Not Started | |
| Phase 7 | — | EKS & GitOps | EKS, ArgoCD, ESO, AWS LBC | ⚪ Not Started | |
| Phase 8 | — | Day-2 Ops & FIS | FIS, DR, EKS/RDS Upgrades | ⚪ Not Started | |