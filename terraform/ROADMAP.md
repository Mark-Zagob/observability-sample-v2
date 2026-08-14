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

- [x] `observability/amp` (Module mới): Tạo Amazon Managed Prometheus workspace. KMS CMK encryption, SSM exports, cardinality alarm.
- [x] `observability/xray`: Enable X-Ray tracing cho ECS Tasks.
- [x] `observability/amg` (Module mới): Tạo Amazon Managed Grafana workspace.
  - Authentication: AWS IAM Identity Center (SSO)
  - Data sources: AMP + X-Ray + CloudWatch — provisioned via Grafana Terraform Provider tại `control-plane/lab-grafana/` (tách state, đọc SSM). Xem [`docs/GRAFANA_PROVIDER_BOOTSTRAP.md`](docs/GRAFANA_PROVIDER_BOOTSTRAP.md).
  - Dashboard as Code: JSON provisioned từ Git (Phase 3 sẽ áp dụng)
- [x] Update `compute/ecs-service` module:
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

- [x] Verify traces xuất hiện trên X-Ray Service Map.
- [x] **Setup Amazon Managed Grafana (AMG):**
  - Tạo AMG workspace qua Terraform (`aws_grafana_workspace`) — `modules/observability/amg/`
  - Configure AWS IAM Identity Center làm identity provider (SSO)
  - Add AMP workspace làm Prometheus data source (SigV4 auth) — `control-plane/lab-grafana/`
  - Add X-Ray + CloudWatch làm data source — `control-plane/lab-grafana/`
  - Import JSON dashboard từ `on-premises/observability-vm/grafana/dashboards/Application/`
- [x] Verify traces xuất hiện trên X-Ray Service Map.
- [x] Verify metrics trên AMP hiển thị đúng trên AMG dashboard.
- [x] Create 1 custom dashboard: "POD 1 — The Illumination" với 4 panels:
  - P95 latency (Order + Payment)
  - Error rate (by HTTP status code)
  - Request rate (by traffic_source)
  - DB pool wait duration

### 🎯 POD 1 Definition of Done

- [x] **Observable**: X-Ray Service Map hiện rõ `Order → Payment → RDS` với latency breakdown
- [x] **Queryable**: AMP có ít nhất 5 metrics: `http_server_duration`, `http_server_request_count`, `db_pool_wait_duration_seconds`, `payment_gateway_duration_seconds`, `orders_created_total`
- [x] **Dashboardable**: AMG workspace deployed và accessible qua SSO
- [x] **Dashboardable**: AMP + X-Ray data sources connected thành công
- [x] **Dashboardable**: 1 custom dashboard "POD 1 — The Illumination" với 4 panels hiển thị real-time data
- [x] **Testable**: Python E2E script bắn 100 requests → verify 100 traces trên X-Ray

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

# 🗄️ PHASE 2: THE CRITICAL PATH (POD 2 — Full Distributed System)

**Mục tiêu:** Deploy và master toàn bộ trục xương sống của E-commerce theo layered approach.

**Thời gian:** 5 tuần (100 hours với 20h/week commitment)

**Rationale:** Thay vì deploy ĐỒNG LOẠT 6 services + 3 stateful resources cùng lúc (big bang), chúng ta áp dụng layered approach — master mỗi layer trước khi add complexity. Điều này giúp:

- Blast radius nhỏ → dễ debug
- Contract testing giữa các layers
- Knowledge transfer qua documentation
- Muscle memory qua repetition

## 📋 Layered Deployment Strategy

| Sub-Phase | Focus | Time | Deliverables |
|-----------|-------|------|---------------|
| 2.1 | The Stateful Foundation (RDS Only) | Week 1 | RDS Multi-AZ + Order/Payment wired + Drill 11 |
| 2.2 | The Cache Layer (ElastiCache) | Week 2 | Redis Replication Group + Cache-aside + Drill 12 |
| 2.3 | The Event Bus (MSK Kafka) | Week 3-4 | MSK Cluster + Producers + Consumers + Drill 13-14 |
| 2.4 | The Edge & Flow (API GW + Web UI) | Week 4-5 | BFF pattern + Traffic Gen + Drill 15 |
| 2.5 | The Validation Week | Week 5 | E2E testing + Dashboards + Runbooks |

---

## 📦 Phase 2.1: The Stateful Foundation — RDS Only (Week 1)

**Mục tiêu:** Deploy RDS Multi-AZ, wire Order/Payment services, thiết lập production-grade database bootstrap pipeline, validate connectivity + failover.

**Production Parallel:** Đây là công việc của DBA/Platform team trong production thực tế. Họ provision database trước, chạy migration pipeline độc lập, validate nó hoạt động, rồi mới "hand-off" cho app teams.

### ⚠️ Architecture Decision: ADR-018 "Database Bootstrap Strategy"

| Approach | Production Grade | Learning Value | Risk |
|----------|------------------|-----------------|------|
| ❌ Option 1: ECS Exec + manual `psql` | Manual, no audit | Low | Human error, no rollback |
| ✅ Tier 2: Dedicated Migration Task | Automated, auditable | High | Migration fail blocks deploy |
| 🆕 Future (EKS): ArgoCD PreSync + Flyway | GitOps-native | Expert | K8s complexity |

**Tại sao KHÔNG dùng app-level migration (`_ensure_schema()`)?**

- **Coupling Anti-Pattern:** App "own" schema → vi phạm separation of concerns (Đã xóa hoàn toàn `_ensure_schema()` khỏi `order-service/app.py`).
- **Blast Radius:** Migration fail = App crash → Zero availability.
- **Privilege Escalation:** App user cần DDL privileges → vi phạm least privilege (App runtime dùng DML-only).
- **No Version Control:** Schema embedded trong code → không có migration history (Chuyển sang `schema_migrations` table tracking).

### 🧩 Modules triển khai

- [ ] Enable `database` module (đã có trong Control Plane) với `multi_az = true`
- [x] 🆕 NEW: Tạo `bootstrap-migration` module (Dedicated Migration ECS Task)
  - Task Definition riêng với DDL-privileged IAM role
  - CloudWatch Log Group riêng cho migration audit trail
  - `null_resource` trigger migration tự động sau khi RDS ready
- [x] 🆕 NEW: Build & Push migration Docker image lên ECR
  - Base image: `postgres:16-alpine` + `aws-cli` + `jq`
  - Entry script: `/usr/local/bin/run-migration.sh`
  - Idempotent & Versioned: `pg_advisory_lock` + `schema_migrations` table + `UNIQUE(name)` on `products`

### 📦 Workload Wiring

```hcl
# 1. Migration Task Definition (terraform/modules/bootstrap-migration/)
resource "aws_ecs_task_definition" "migration" {
  family                   = "${var.project_name}-${var.environment}-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.migration.arn  # ← DDL-privileged role

  container_definitions = jsonencode([{
    name  = "migration"
    image = var.migration_image
    environment = [
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_SECRET_ARN", value = var.db_secret_arn }
    ]
  }])
}

# 2. IAM Role Separation (Least Privilege)
#    Migration Role: DDL (CREATE, ALTER, DROP) + Secrets read
#    App Role:       DML only (SELECT, INSERT, UPDATE, DELETE)

# 3. Auto-trigger migration sau khi RDS ready
resource "null_resource" "run_migration" {
  depends_on = [aws_ecs_task_definition.migration]
  triggers = {
    task_definition_arn = aws_ecs_task_definition.migration.arn
  }
  provisioner "local-exec" {
    command = <<-EOT
      aws ecs run-task --cluster ${var.ecs_cluster_name} \
        --task-definition ${aws_ecs_task_definition.migration.arn} \
        --launch-type FARGATE \
        --network-configuration "..."
      aws ecs wait tasks-stopped --tasks "$TASK_ARN"
      # Check exit code → fail terraform apply nếu migration fail
    EOT
  }
}
```

```hcl
# 4. Wire Order/Payment services → RDS
# data-plane/order-service/main.tf
environment = {
  ENABLE_REDIS    = "false"  # ← Vẫn disable (Phase 2 khi có ElastiCache)
  ENABLE_KAFKA    = "false"  # ← Vẫn disable (Phase 2 khi có MSK)
}
secrets = {
  DB_SECRET = data.aws_ssm_parameter.db_app_secret_arn.value  # ← DML-only app_user
}
```

### 🧪 Bootstrap Migration Pipeline (Tier 2)

**Flow:**

```
Terraform Apply (Control Plane)
     │
     ├─► RDS Provisioned (Multi-AZ)
     ├─► Secrets Manager Secret Created
     ├─► Migration Task Definition Created
     │
     ▼
Migration Task (runs once, ~30s)
     │
     ├─► Read secret from Secrets Manager
     ├─► Connect to RDS with DDL role (SSL mode: require)
     ├─► Acquire advisory lock (pg_advisory_lock)
     ├─► Execute init-app.sql (Idempotent + Versioned 2.1.0)
     ├─► SQL Verification (RAISE EXCEPTION if tables < 6 or products != 5)
     ├─► Release advisory lock (only after 100% verification success)
     │
     ▼
Exit 0 (success) → App services deploy
Exit 1 (fail)    → Block app deployment + Telegram alert
```

**Key Design Decisions:**

| Decision | Rationale |
|----------|-----------|
| Separate IAM role | DDL privileges isolated from app runtime |
| CloudWatch Logs | Full audit trail cho mọi migration |
| Advisory lock | Prevent concurrent migration tasks (multi-AZ safe) |
| Fail-fast exit code | Block app deploy nếu schema không sẵn sàng |
| Single Source of Truth Verification | SQL block tự verify & `RAISE EXCEPTION` trong transaction trước khi release advisory lock |
| Schema Versioning | Bảng `schema_migrations` theo dõi version (2.1.0) giống Flyway/Liquibase |
| Natural Key Unique Constraint | `products.name UNIQUE` đảm bảo seed data 100% idempotent, không nhân đôi |

### 💥 Chaos Drills

**Drill 11: The DB Earthquake** — `aws rds reboot-db-instance --force-failover`

> ⚠️ **Redesigned**: Success criteria cũ ("reconnect < 5s", "zero lost orders") bất khả thi
> với kiến trúc hiện tại. AWS Multi-AZ failover = 60–120s, TCP keepalive phát hiện dead
> connection sau ~105s (`idle=60 + 3×15`), `retry_connect()` chỉ retry khi tạo pool mới,
> `execute()` không có query-level retry. Trong cửa sổ failover **chắc chắn có 5xx**.
> Tư duy: đo sự thật, rồi quyết định đầu tư gì để đóng gap.

**Protocol: 2 Runs**

**RUN A — Đo sự thật (bắt buộc):**

```bash
# Terminal 1: Traffic nền (5 phút, 1 request/2s)
for i in $(seq 1 150); do
  echo "$(date +%H:%M:%S) $(curl -s -o /dev/null -w '%{http_code}' \
    -X POST https://app.bd-apa-coi.com/process \
    -H 'Content-Type: application/json' \
    -d '{"product_id": 1, "quantity": 1}')" >> /tmp/drill11_runA.txt
  sleep 2
done

# Terminal 2: Inject sau ~30s traffic nền
aws rds reboot-db-instance --db-instance-identifier obs-lab-postgres --force-failover

# Terminal 3: Watch metrics
# - db_pool_wait_duration_seconds (spike)
# - http_request_duration_seconds (spike)
# - X-Ray traces (error spans)
```

**Bảng đo lường (điền vào post-mortem — đây là deliverable):**

| Metric | Kỳ vọng lý thuyết | Thực đo |
|--------|-------------------|---------|
| Failover duration (RDS Events console) | 60–120s | ___ |
| Request 5xx đầu tiên sau inject | +0–15s | ___ |
| Request 200 đầu tiên sau recovery | +60–150s | ___ |
| Tổng failed / tổng requests | > 0 (không có retry layer) | ___ |
| User Pain Score thực đo | — | ___ % |
| Alert Telegram nào fire? | Có thể KHÔNG → blind spot đáng ghi nhận | ___ |
| Cần human can thiệp? | Kỳ vọng: KHÔNG | ___ |

**Success Criteria (realistic):**

- ✅ App tự phục hồi không cần human intervention
- ✅ RTO thực tế được đo và ghi vào post-mortem
- ✅ Metrics/traces trong cửa sổ failover query được (observability hoạt động)
- ✅ User Pain Score được đo, không giả định
- 📝 "Zero lost orders" → chuyển thành finding: "X orders failed → decision: có đáng đầu tư request-level retry không?"

**RUN B — Cải thiện (stretch, chỉ nếu Run A cho thấy đáng đầu tư):**

> ⚠️ Retry cho SELECT thì an toàn, nhưng retry cho INSERT orders thì không an toàn
> nếu không có idempotency key (tạo đơn hàng đôi). Production dùng idempotency key + retry
> cùng nhau. Nếu không làm Run B: ghi vào ADR rằng gap sẽ được giải quyết bởi
> RDS Proxy (Phase 4) — proxy che phần lớn failover khỏi app.

- Thêm connection-level + SELECT-only retry trong `shared/db_utils.py`
- Đo lại, so sánh trước/sau
- Ghi kết quả vào post-mortem

🆕 **Drill 11.5: The Migration Sabotage** — Inject bad SQL vào `init-app.sql`

- **Pre-flight:** Verify migration pipeline working với good SQL
- **Inject:**

```sql
  -- Modify init-app.sql with syntax error
  CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    INVALID_SYNTAX_HERE  -- ← Error
  );
```

```bash
  # ⚠️ Sửa SQL phải đi kèm rebuild + push image tag mới
  # (SQL baked vào Docker image, không mount runtime)
  docker build -t migration:v1.1.0-bad .
  docker push <ecr>/migration:v1.1.0-bad
  # Bump image_tags["migration"] = "v1.1.0-bad" → terraform apply control-plane
```

- **Observe:**
  - Migration task fails với exit code 1
  - CloudWatch Logs `/ecs/obs/lab/migration` show `psql` error
  - SSM Gate ghi `status=FAILED`
  - Data Plane `check "migration_gate"` chặn deploy

**Machine-Verifiable Success Criteria:**

| Check | Lệnh verify | Kỳ vọng |
|-------|-------------|---------|
| Migration task fail | CloudWatch logs `/ecs/obs/lab/migration` | psql syntax error, exit 1 |
| Gate ghi FAILED | `aws ssm get-parameter --name "/obs/lab/migration/status"` | `"FAILED"` |
| Data Plane bị chặn | `cd data-plane/order-service && terraform plan` | 🛑 `check "migration_gate"` error |
| Recovery | Sửa SQL → rebuild `v1.1.1` → bump tag → apply control → apply data | `status = SUCCESS`, data plane pass |
| Thời gian recovery | Bấm giờ toàn bộ | < 5 phút |

- **Recovery:**
  - Fix SQL syntax
  - Rebuild migration image với **new tag** (e.g., `v1.1.1`)
  - Apply control-plane → migration SUCCESS → gate = SUCCESS
  - Apply data-plane → `check "migration_gate"` pass → deploy
- **Learning Value:**
  - Hiểu blast radius của migration failure
  - Practice incident response với schema issues
  - Validate SSM Gate pattern (cross-state blocking)
  - Validate "fail-fast" design principle

### 📖 Skills bạn sẽ master

| Skill | Level | Production Application |
|-------|-------|--------------------------|
| RDS Multi-AZ | Expert | Design HA databases, measure actual RTO |
| Secrets Manager Integration | Advanced | Zero-hardcoded credentials, auto-rotation |
| IAM Separation (DDL vs DML) | Expert | Least privilege cho database access |
| ECS Task Lifecycle | Advanced | One-shot tasks, exit code handling |
| PostgreSQL Advisory Locks | Advanced | Prevent DDL race conditions |
| Terraform `null_resource` | Advanced | Orchestrate cross-resource workflows |
| Migration Pipeline Design | Expert | Production-grade schema management |
| TCP Keep-Alive + `statement_timeout` | Advanced | Already in codebase! |

### 📝 Definition of Done

**Infrastructure:**

- [ ] RDS Multi-AZ deployed với `db.t3.micro`
- [ ] Migration ECR image built & pushed
- [ ] Migration IAM role với DDL privileges (separate from app role)
- [ ] Migration task tự động chạy sau khi RDS ready

**Bootstrap Pipeline:**

- [ ] Migration task tạo ≥ 5 tables + seed data
- [ ] CloudWatch Logs hiển thị full migration audit trail
- [ ] Migration failure blocks app deployment (verified via Drill 11.5)
- [ ] Advisory lock hoạt động khi 2 migration tasks chạy đồng thời

**App Integration:**

- [ ] Order Service connect thành công, query products từ RDS
- [ ] App role KHÔNG có DDL privileges (verified qua SQL negative test: `CREATE TABLE` bị block)
- [ ] Zero hardcoded credentials trong app code

**Resilience:**

- [ ] Drill 11 passed: App tự phục hồi sau failover, RTO thực tế được đo và ghi post-mortem
- [ ] Drill 11.5 passed: Migration failure → SSM gate FAILED → Data Plane bị chặn
- [ ] X-Ray trace: Order Service → RDS với failover visible

**Documentation:**

- [ ] Runbook section: "RDS Failover Recovery" written
- [ ] Runbook section: "Migration Failure Recovery" written
- [ ] ADR-018: "Database Bootstrap Strategy" documented

**FinOps:**

- [ ] Destroy RDS khi không dùng để tiết kiệm cost (~$3/day)
- [ ] Migration task runs < 1 phút (cost < $0.01 per run)

---

## ⚡ Phase 2.2: The Cache Layer — ElastiCache Redis (Week 2)

**Mục tiêu:** Deploy ElastiCache Replication Group, wire cache-aside pattern + Payment idempotency.

**Production Parallel:** Đây là công việc của Platform team hoặc Senior SRE. Redis thường được provisioned như "shared infrastructure" mà nhiều services dùng chung.

### 🧩 Modules triển khai

- [ ] Deploy `cache` module (Module 5 từ Terraform Playbook)
  - ElastiCache Replication Group (1 shard, 2 nodes)
  - Auth Token + Transit Encryption
  - CloudWatch Alarms (CPU, memory, connections, replication lag)
- [ ] Export metadata to SSM: `/obs/lab/cache/*`

### 📦 Workload Wiring

```hcl
# data-plane/order-service/main.tf
data "aws_ssm_parameter" "redis_endpoint" {
  name = "/obs/lab/cache/endpoint"
}

environment = {
  # ... existing vars ...
  REDIS_URL    = "redis://${data.aws_ssm_parameter.redis_endpoint.value}:6379"
  ENABLE_REDIS = "true"  # ← Bật lại
  ENABLE_KAFKA = "false" # ← Vẫn disable
}
```

### 💥 Chaos Drills

**Drill 12: The Cache Avalanche** — Flush Redis hoặc kill replica node

- **Pre-flight:** Verify cache hit rate > 80% dưới normal load
- **Inject:** `redis-cli -h <endpoint> -a <auth_token> FLUSHALL` hoặc delete 1 replica node
- **Observe:**
  - Cache miss storm → DB connection pool saturation
  - Metric: `cache_operations_total{result="miss"}` spike
  - Metric: `db_pool_wait_duration_seconds` tăng
  - Business Impact: P95 latency từ 100ms → 500ms, nhưng KHÔNG có errors
- **Success Criteria:**
  - App không crash (graceful degradation)
  - Cache hit rate phục hồi > 80% sau 5 phút
  - DB connections không exhaust (nhờ pool sizing đúng)

### 📖 Skills bạn sẽ master

- Redis Replication Group vs Cluster Mode (trade-off)
- Cache-aside pattern với TTL (đã có trong code!)
- Idempotency State Machine (đã có trong `shared/idempotency.py`!)
- Graceful Degradation: Redis down = cache miss, không phải outage

### 📝 Definition of Done

- [ ] ElastiCache Replication Group deployed (cost ~$2/day)
- [ ] Order Service cache hit rate > 80% dưới load
- [ ] Payment idempotency working (duplicate request trả cached result)
- [ ] Drill 12 passed: Cache avalanche handled gracefully
- [ ] X-Ray trace: Order Service → Redis → (miss) → RDS
- [ ] Runbook section: "Redis Failover & Cache Miss Storm" written

---

## 📨 Phase 2.3: The Event Bus — MSK Kafka (Week 3-4)

**Mục tiêu:** Deploy MSK Kafka (KRaft), wire producers + consumers, validate event-driven flow.

**Production Parallel:** Đây là công việc của Event/Streaming team hoặc Data Platform team. Kafka là "central nervous system" của hệ thống.

### 🧩 Modules triển khai

- [ ] Deploy `streaming` module (Module 6 từ Terraform Playbook)
  - MSK Kafka cluster (KRaft mode, 2 brokers, 3 partitions)
  - IAM authentication (không dùng SASL/SCRAM)
  - CloudWatch Alarms (under-replicated partitions, offline partitions, disk usage)
- [ ] Export metadata to SSM: `/obs/lab/streaming/*`

### 📦 Workload Wiring

```hcl
# data-plane/order-service/main.tf
data "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name = "/obs/lab/streaming/bootstrap_servers"
}

environment = {
  # ... existing vars ...
  KAFKA_BOOTSTRAP_SERVERS = data.aws_ssm_parameter.kafka_bootstrap_servers.value
  ENABLE_KAFKA            = "true"  # ← Bật lại
}
```

### 📦 Workload Onboard (Async Workers)

- [ ] Deploy Notification Worker (`data-plane/notification-worker/`)
  - Kafka consumer với `enable.auto.commit = false` (manual commit)
  - Idempotent processing via `processed_events` table
  - OTel trace context propagation from Kafka headers
- [ ] Deploy Inventory Worker (`data-plane/inventory-worker/`)
  - Kafka consumer với pessimistic locking (`SELECT FOR UPDATE`)
  - Auto-restock logic khi stock < threshold
  - Audit trail via `inventory_log` table

### 💥 Chaos Drills

**Drill 13: The Kafka Partition** — Kill 1 MSK broker

- **Pre-flight:** Verify consumer lag < 100 messages dưới normal load
- **Inject:** Reboot 1 MSK broker hoặc block SG port 9092 của 1 broker
- **Observe:**
  - Partition leader election (~30s)
  - Consumer lag spike
  - Metric: `kafka_consumer_lag` tăng, `kafka_events_consumed_total` tạm dừng
  - Recovery: Consumers tự reconnect, process backlog
- **Success Criteria:**
  - Workers tự động resume consume từ offset cũ
  - Không mất message (at-least-once delivery)
  - Consumer lag < 100 messages sau 1 phút recovery

**Drill 14: The Zombie Consumer** — Stop Notification Worker task

- **Pre-flight:** Verify cả 2 workers đang consume
- **Inject:**

```bash
  aws ecs stop-task --cluster obs-cluster --task <task-id>
```

- **Observe:**
  - Consumer group rebalance
  - Messages accumulate trong Kafka
  - Metric: `kafka_consumer_lag{group="notification-workers"}` tăng liên tục
  - Recovery: Task mới start, catch up backlog
- **Success Criteria:**
  - Graceful Shutdown handler commit offset TRƯỚC khi process exit
  - Không duplicate processing (nhờ idempotency)
  - Consumer lag về 0 sau khi task mới catch up

### 📖 Skills bạn sẽ master

- MSK KRaft vs ZooKeeper (trade-off)
- Partition strategy (key-based partitioning với `order_id`)
- Consumer group rebalancing
- At-least-once delivery + idempotency
- Kafka producer natural batching (đã có trong code!)
- Manual commit pattern (đã có trong code!)

### 📝 Definition of Done

- [ ] MSK Kafka cluster deployed (cost ~$5/day)
- [ ] Order Service publish events thành công (natural batching working)
- [ ] Notification + Inventory Workers consume events, process idempotently
- [ ] Drill 13 passed: MSK broker loss tự recover trong < 1 phút
- [ ] Drill 14 passed: Zero message loss during rolling updates
- [ ] X-Ray trace: Order Service → (Kafka) → Notification Worker
- [ ] Runbook section: "Kafka Partition Leader Election" + "Consumer Lag Recovery" written

---

## 🌐 Phase 2.4: The Edge & Flow — API GW + Web UI + Traffic Gen (Week 4-5)

**Mục tiêu:** Deploy edge layer, hoàn thiện full distributed flow, validate end-to-end.

**Production Parallel:** Đây là công việc của Platform team (API GW) và Frontend team (Web UI). Traffic Generator là của SRE team để synthetic testing.

### 🧩 Modules triển khai

- [ ] Deploy API Gateway service (`data-plane/api-gateway/`)
  - BFF pattern (Backend for Frontend)
  - RFC 7807 error propagation
  - Traffic source tagging (synthetic vs organic)
- [ ] Deploy Web UI service (`data-plane/web-ui/`)
  - Nginx với traffic tagging via Page Visibility API
  - Auto-refresh pause khi tab hidden
- [ ] Deploy Traffic Generator service (`data-plane/traffic-gen/`)
  - Synthetic load testing với scenarios (normal, flash_sale, event_driven)
- [ ] Update `loadbalancer` module: thêm API GW target group
- [ ] Wire ALB → API GW → Order Service (thay vì ALB → Order trực tiếp)

### 📦 Workload Wiring

```hcl
# Update loadbalancer module
alb_services = {
  "api-gateway" = {
    port          = 5000
    health_path   = "/health/live"
    path_patterns = ["/*"]
    priority      = 100
  }
}

# data-plane/order-service/main.tf
environment = {
  # ... existing vars ...
  # Order Service không còn expose ra ALB trực tiếp
  # Chỉ API Gateway gọi qua Cloud Map DNS
}
```

### 💥 Chaos Drills

**Drill 15: The Graceful Guillotine** — ECS Stop Task trong khi có in-flight requests

- **Pre-flight:** Verify Traffic Generator đang chạy scenario "normal"
- **Inject:**

```bash
  aws ecs stop-task --cluster obs-cluster --task <order-service-task-id>
```

- **Observe:**
  - Kafka producer flush (10s timeout)
  - DB pool close (5s)
  - Redis close (5s)
  - Metric: `ecs_task_stopped_abnormal` event KHÔNG fire (graceful shutdown)
  - Business Impact: Zero lost Kafka messages, zero DB connection leaks
- **Success Criteria:**
  - Zero dropped Kafka messages
  - Zero ghost DB connections
  - Task mới start và resume traffic seamlessly

### 📖 Skills bạn sẽ master

- BFF pattern (Backend for Frontend)
- RFC 7807 error propagation (đã có trong code!)
- Synthetic traffic vs organic traffic tagging (đã có trong code!)
- Graceful shutdown orchestration (đã có trong code!)
- Page Visibility API (đã có trong code!)

### 📝 Definition of Done

- [ ] API Gateway deployed, wire ALB → API GW → Order Service
- [ ] Web UI accessible qua ALB, traffic tagging working
- [ ] Traffic Generator chạy scenario "flash_sale" → 100% orders successful
- [ ] Drill 15 passed: Zero message loss during rolling updates
- [ ] Full X-Ray trace: Web UI → ALB → API GW → Order → Payment → RDS + Kafka → Workers
- [ ] Runbook section: "Graceful Shutdown Orchestration" written

---

## ✅ Phase 2.5: The Validation Week (Week 5 — nửa sau)

**Mục tiêu:** Integration testing, documentation, Grafana dashboards.

### 🎯 Deliverables

- [ ] End-to-end test script (Python):
  - Tạo 100 orders qua Traffic Generator
  - Verify 100 notifications trong Notification Worker
  - Verify 100 inventory updates trong Inventory Worker
  - Verify 100 X-Ray traces xuyên suốt full flow
- [ ] Grafana dashboard "POD 2 — The Critical Path" (6 panels):
  - Request rate (by `traffic_source`)
  - Error rate (by HTTP status code)
  - P95 latency (Order + Payment)
  - DB pool wait duration
  - Cache hit rate
  - Kafka consumer lag
- [ ] Runbook hoàn chỉnh cho 5 Chaos Drills (11-15)
- [ ] Post-mortem template cho mỗi drill
- [ ] Architecture Decision Records (ADRs) cho các decisions lớn:
  - ADR-014: "RDS Multi-AZ vs Single-AZ trade-off"
  - ADR-015: "ElastiCache Replication Group vs Cluster Mode"
  - ADR-016: "MSK KRaft vs ZooKeeper"
  - ADR-017: "Manual Kafka Commit vs Auto-Commit"

### 📝 Definition of Done

- [ ] All 5 Chaos Drills (11-15) passed với documented outcomes
- [ ] Grafana dashboard visualize full POD 2 health
- [ ] Runbook có thể được "người khác" (future you) follow để recover incidents
- [ ] POD 2 Definition of Done hoàn thành 100%
- [ ] Destroy expensive resources (MSK, Multi-AZ RDS) khi không dùng

### 💥 SRE / Chaos Drills (POD 2 — Stateful Chaos)

| # | Drill | Blast Radius | Sub-Phase | Skill học được |
|---|-------|--------------|-----------|-----------------|
| 11 | The DB Earthquake (RDS Multi-AZ Failover) | RDS + Order + Payment | 2.1 | `aws rds reboot-db-instance --force-failover`, `psycopg2` retry logic |
| 12 | The Cache Avalanche (Redis Flush) | ElastiCache + Order Service | 2.2 | Cache miss storm, DB connection pool saturation |
| 13 | The Kafka Partition (MSK Broker Loss) | MSK + Workers | 2.3 | Partition leader election, consumer group rebalance |
| 14 | The Zombie Consumer (Stop Worker) | Notification/Inventory Worker | 2.3 | Consumer lag detection, offset commit behavior |
| 15 | The Graceful Guillotine (ECS Stop Task) | 1 ECS Task | 2.4 | SIGTERM handling, Kafka buffer flush, DB pool close |

### ✅ POD 2 Definition of Done

**Observable:**
- [ ] 1 full X-Ray trace: Web UI → ALB → API GW → Order → Payment → RDS + Kafka event flow visible
- [ ] Grafana dashboard "POD 2 — The Critical Path" với 6 panels hiển thị real-time data

**Resilient:**
- [ ] RDS Multi-AZ failover transparent với app (nhờ `retry_connect`)
- [ ] ElastiCache auto-failover < 30s, app graceful degradation
- [ ] MSK broker loss tự recover trong < 1 phút

**Efficient:**
- [ ] Verify RDS/Redis/MSK traffic KHÔNG đi qua NAT Gateway (dùng VPC Flow Logs + Athena)
- [ ] Cache hit rate > 80% dưới normal load
- [ ] Kafka producer natural batching working (linger.ms=50, batch.size=16KB)

**Graceful:**
- [ ] Kafka producer flush thành công khi ECS scale-in/stop task
- [ ] DB pool close + Redis close on SIGTERM
- [ ] Zero ghost connections sau rolling updates

**Testable:**
- [ ] Web UI có thể tạo order → thấy notification trong Notification Worker → thấy stock giảm trong Inventory Worker
- [ ] Traffic Generator chạy scenario "flash_sale" → 100% orders successful
- [ ] E2E test script: 100 orders → 100 notifications → 100 inventory updates

**Documented:**
- [ ] 5 Runbook sections cho Chaos Drills 11-15
- [ ] 4 ADRs cho architectural decisions
- [ ] Post-mortem template cho mỗi drill

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
|---|---|---|---|---|---|
| Phase 1 | — | Sync Tracer Bullet | Order, Payment (ECS Fargate) | ✅ DONE | Chaos Drills 1-3.5 done. Identified gaps: Observability, API GW, SIGTERM handler |
| Phase 1.5 | POD 1 | The Illumination | AMP, X-Ray, ADOT Sidecar, AMG | 🟡 In Progress | AMP + AMG modules done. Grafana data sources tách state. Còn: ADOT sidecar wiring, dashboard import, verify e2e |
| **Phase 2.1** | **POD 2** | **Stateful Foundation** | **RDS Multi-AZ + Order/Payment wired** | **⚪ Not Started** | **Mục tiêu: RDS failover transparent** |
| **Phase 2.2** | **POD 2** | **Cache Layer** | **ElastiCache + Cache-aside pattern** | **⚪ Not Started** | **Mục tiêu: Cache miss storm handled gracefully** |
| **Phase 2.3** | **POD 2** | **Event Bus** | **MSK Kafka + Producers + Consumers** | **⚪ Not Started** | **Mục tiêu: Event-driven flow end-to-end** |
| **Phase 2.4** | **POD 2** | **Edge & Flow** | **API GW + Web UI + Traffic Gen** | **⚪ Not Started** | **Mục tiêu: Full distributed flow** |
| **Phase 2.5** | **POD 2** | **Validation** | **E2E testing + Dashboards + Runbooks** | **⚪ Not Started** | **Mục tiêu: Production-ready POD 2** |
| Phase 2.7 🆕 | POD 3 | The Chaos Dojo | AWS FIS, DR, Full-stack Chaos Drills | ⚪ Not Started | Mục tiêu: Self-healing validation + incident response |
| Phase 3 | — | Platform Shield | Bastion, CI/CD (OIDC+OPA), Budgets | ⚪ Not Started | |
| Phase 4 | — | Security & Pooling | Auth (#7), RDS Proxy | ⚪ Not Started | |
| Phase 5 | — | Saga Workflows | Shipping Svc, Worker (#8, #9) | ⚪ Not Started | |
| Phase 6 | — | CQRS & Search | OpenSearch, Search Svc (#10) | ⚪ Not Started | |
| Phase 7 | — | EKS & GitOps | EKS, ArgoCD, ESO, AWS LBC | ⚪ Not Started | |
| Phase 8 | — | Day-2 Ops & FIS | FIS, DR, EKS/RDS Upgrades | ⚪ Not Started | |