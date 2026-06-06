# 🔭 Observability & Reliability Lab — E-Commerce Microservices

> Dự án học tập chuyên sâu về **Observability**, **SRE** và **Cloud Engineering** thông qua việc xây dựng hệ thống e-commerce microservices hoàn chỉnh.
> Bao gồm full-stack monitoring (Metrics, Logs, Traces), Incident Management, Chaos Engineering và Infrastructure-as-Code trên AWS.

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker) ![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python) ![Observability](https://img.shields.io/badge/Observability-OTel%20%7C%20Prometheus%20%7C%20Loki%20%7C%20Tempo-orange) ![SRE](https://img.shields.io/badge/SRE-SLO%20%7C%20Error%20Budget%20%7C%20Chaos-red) ![Terraform](https://img.shields.io/badge/IaC-Terraform%20%7C%20OPA-7B42BC?logo=terraform)

---

## 📋 Mục Lục

- [Tổng Quan](#-tổng-quan)
- [Kiến Trúc Hệ Thống](#️-kiến-trúc-hệ-thống)
- [Cấu Trúc Repository](#-cấu-trúc-repository)
- [On-Premises (Docker Compose)](#-on-premises--docker-compose)
- [Terraform — AWS](#️-terraform--aws)
- [CI/CD Pipeline](#️-cicd-pipeline)
- [Hướng Dẫn Bắt Đầu](#-hướng-dẫn-bắt-đầu)
- [Tài Liệu Tham Khảo](#-tài-liệu-tham-khảo)

---

## 🎯 Tổng Quan

Dự án này bao gồm **hai môi trường** — cùng hệ thống microservices, khác nhau về hạ tầng và vận hành:

| Môi trường | Trạng thái | Mô tả |
|-----------|-----------|-------|
| **[On-Premises](on-premises/)** (Docker Compose) | ✅ Production-ready Lab | 6 microservices + full observability stack trên 2 VMs. Bao gồm Incident Management, Chaos Engineering, Break/Test/Recovery drills, Post-Mortem templates |
| **[Terraform — AWS](terraform/)** | 🔄 Foundation done, Compute in progress | Infrastructure-as-Code cho AWS (VPC, RDS, Security, Policy-as-Code). Roadmap tới ECS/EKS, MSK, DR Strategy |

### Bạn sẽ học được gì?

| Lĩnh vực | Nội dung |
|---------|---------|
| **Microservices Architecture** | Event-driven (Kafka KRaft), sync HTTP, BFF pattern, shared library |
| **Observability 3 Pillars** | Metrics (Prometheus), Logs (Loki), Traces (Tempo) + Correlation via `trace_id` |
| **Distributed Tracing** | Trace propagation qua Kafka message headers (W3C TraceContext) |
| **Alerting & SLO** | Alertmanager → Telegram, Multi-Window Multi-Burn-Rate (MWMBR), SLI/SLO, Error Budget |
| **Application Instrumentation** | Custom metrics (Counter, Histogram), manual spans, structured logging, OTel SDK |
| **SRE & Incident Management** | Runbook-driven response, Blameless Post-Mortem, 5 Whys, SEV Matrix |
| **Chaos Engineering** | Break/Test/Recovery drills cho PostgreSQL, Kafka, Redis, Prometheus |
| **Infrastructure-as-Code** | Terraform modules, OPA policy-as-code, CI/CD với GitHub Actions |
| **Design Patterns** | Idempotency, Cache-Aside, Pessimistic Locking, RFC 7807 Problem Details |

---

## 🏗️ Kiến Trúc Hệ Thống

### On-Premises — 2 VMs, Docker Compose

```text
┌───────────────────────────────────────────────────────────────────┐
│                      Applications VM                              │
│                                                                   │
│  [Web UI] ──► [API Gateway] ──► [Order Service] ──► [Payment Svc] │
│   (Nginx)       (BFF / JWT)      (Postgres/Redis)   (Simulated)   │
│                                      │                            │
│                                      ▼                            │
│                  ┌──────────── Kafka (KRaft) ──────────────┐      │
│                  │                                         │      │
│                  ▼                                         ▼      │
│         [Inventory Worker]                       [Notification]   │
│         (Pessimistic Lock)                       (Idempotency)    │
│                                                                   │
│  [Traffic Generator] ──► (Load Testing / Chaos Scenarios)         │
└──────────────────────────────┬────────────────────────────────────┘
                               │ OTLP (gRPC :4317) / Metrics / Logs
┌──────────────────────────────▼────────────────────────────────────┐
│                     Observability VM                               │
│                                                                   │
│  [OTel Collector] ──► [Prometheus] ◄── [Blackbox Exporter]        │
│        │                  │                                       │
│        ├─────────────► [Tempo]      [Alertmanager] ──► Telegram   │
│        └─────────────► [Loki]             │                       │
│                           │               ▼                       │
│                           └──────► [Grafana] (Dashboards/SLO)     │
│                                                                   │
│  [MinIO] ◄── (S3-compatible Storage for Loki/Tempo)               │
└───────────────────────────────────────────────────────────────────┘
```

> 📖 Chi tiết kiến trúc, data flows, DB schema: xem [`on-premises/ARCHITECTURE.md`](on-premises/ARCHITECTURE.md)

### AWS — Production-Grade (Terraform)

```text
Internet → Route53 → WAF → ALB → Compute (ECS/EKS) → RDS + ElastiCache + MSK
                                                     → Observability (AMP/X-Ray/CloudWatch)
```

> 📖 Chi tiết AWS: xem [`terraform/ARCHITECTURE.md`](terraform/ARCHITECTURE.md)

---

## 📁 Cấu Trúc Repository

```
observability-sample-v2/
│
├── on-premises/                            # ✅ Docker Compose — Production-Grade Lab
│   ├── README.md                          # Getting started, learning roadmap, navigation guide
│   ├── ARCHITECTURE.md                    # Kiến trúc, data flows, DB schema, design patterns
│   ├── EXPANSION_PLAN.md                  # Roadmap 6 → 10 services (Saga, CQRS, Circuit Breaker)
│   ├── INCIDENT_SIMULATION_GUIDE.md       # 12 chaos experiments — DB lock, Kafka lag, phantom alerts
│   ├── INCIDENT_RUNBOOK.md                # 24 alert runbooks — SEV matrix, escalation, recovery
│   ├── BREAK_TEST_RECOVERY.md             # 28 drills — phá & khôi phục PostgreSQL, Kafka, Redis, Prometheus
│   ├── devops-question.md                 # DevOps interview — junior/mid (45 câu)
│   ├── devops-question-senior.md          # DevOps interview — senior/staff (31 câu)
│   │
│   ├── applications-vm/                   # VM chạy ứng dụng
│   │   ├── applications/
│   │   │   ├── docker-compose.yml         # Multi-service orchestration
│   │   │   ├── init.sql                   # Database schema + seed data
│   │   │   ├── shared/                    # Platform library (OTel setup, DB pools, health checks)
│   │   │   ├── api-gateway/              # BFF routing (Flask :5000)
│   │   │   ├── order-service/            # Core business logic + Kafka producer
│   │   │   ├── payment-service/          # Simulated payment (Flask :5002)
│   │   │   ├── notification-worker/      # Kafka consumer → notifications
│   │   │   ├── inventory-worker/         # Kafka consumer → stock management
│   │   │   ├── traffic-gen/              # API-controlled load testing
│   │   │   └── web-ui/                   # Nginx SPA dashboard
│   │   └── agents/                        # Grafana Alloy (log collection)
│   │
│   ├── observability-vm/                  # VM chạy monitoring stack
│   │   ├── storage/                       # MinIO (S3-compatible backend)
│   │   ├── phase1-metrics/               # Prometheus, Alertmanager, Blackbox Exporter
│   │   ├── phase2-logging/               # Loki, Alloy
│   │   ├── phase3-tracing/               # Tempo, OTel Collector
│   │   └── scripts/                       # annotate.sh, deploy.sh
│   │
│   └── post-mortems/                      # Blameless Post-Mortem templates & examples
│       ├── 00-TEMPLATE.md                # Chuẩn hóa format (5 Whys, Action Items)
│       └── 01-GOLDEN-EXAMPLE-*.md        # Ví dụ mẫu — DB Saturation incident
│
├── terraform/                             # 🔄 AWS IaC — Foundation done
│   ├── README.md                         # Learning objectives, navigation, anti-patterns
│   ├── ARCHITECTURE.md                   # AWS blueprint — VPC topology, compute phases
│   ├── AWS_TERRAFORM_PLAYBOOK.md         # Module-by-module deployment playbook
│   ├── bootstrap/                        # S3 state backend + DynamoDB lock + KMS
│   ├── environments/
│   │   ├── shared/                       # Shared infra (VPC, Security, RDS)
│   │   └── dev/                          # Dev environment (Terraform Cloud backend)
│   ├── modules/
│   │   ├── network/                      # VPC, subnets, NAT, route tables
│   │   ├── security/                     # Security groups, IAM roles
│   │   ├── database/                     # RDS PostgreSQL Multi-AZ
│   │   ├── vpc-endpoints/                # Private connectivity tới AWS services
│   │   ├── logging-flow-logs/            # S3 + Athena for flow log archive + KMS
│   │   └── backup/                       # AWS Backup vault, plans, compliance reports
│   ├── policy/                           # OPA/Rego policy-as-code (14 policies + tests)
│   ├── docs/                             # Deep-dive documentation
│   │   ├── TRADE_OFFS.md                # Architecture decision records
│   │   ├── FINOPS.md                    # AWS cost management & optimization
│   │   └── chaos-exercises-network.md   # 12 break/test/recover exercises
│   └── interviews/                       # DevOps interview questions
│       └── devops-question-m1-iac-core.md  # 54 câu hỏi IaC (Terraform, state, modules)
│
└── .github/workflows/                    # CI/CD Pipelines
    ├── ci.yml                            # Main CI pipeline
    ├── ci-api-gateway.yml                # API Gateway CI
    ├── terraform-policy.yml              # Terraform policy validation (OPA)
    ├── terraform-drift.yml               # Nightly drift detection + Slack/Telegram alerts
    ├── _reusable-build-push.yml          # Reusable: Docker build & push (ECR + GHCR)
    └── _reusable-lint-test.yml           # Reusable: lint + test
```

---

## 🐳 On-Premises — Docker Compose

> 📖 **Hướng dẫn chi tiết:** xem [`on-premises/README.md`](on-premises/README.md)

### Application Services

| Service | Port | Tech | Vai trò |
|---------|------|------|---------|
| **Web UI** | 8580 | Nginx | SPA dashboard — orders, events, load testing |
| **API Gateway** | 5000 | Flask | BFF pattern — routing, aggregation, error propagation |
| **Order Service** | 5001 | Flask | Tạo order, gọi payment, publish Kafka events |
| **Payment Service** | 5002 | Flask | Simulated payment (configurable latency/errors) |
| **Notification Worker** | 5004 | Flask | Kafka consumer → xử lý notifications |
| **Inventory Worker** | 5005 | Flask | Kafka consumer → quản lý stock (pessimistic locking) |
| **Traffic Generator** | 5003 | Flask | Load testing với scenario templates |

### Infrastructure Services

| Service | Port | Vai trò |
|---------|------|---------|
| **PostgreSQL 16** | 5432 | Database chính — orders, products, notifications, inventory |
| **Redis 7** | 6379 | Cache layer — product catalog (TTL 60s) |
| **Kafka 3.7 (KRaft)** | 9092 | Event streaming — không cần ZooKeeper |
| **Kafka UI** | 8585 | Web UI cho topic/consumer inspection |

### Observability Stack (VM riêng)

| Tool | Port | Vai trò |
|------|------|---------|
| **OTel Collector** | 4317/4318 | Thu nhận OTLP traces/metrics/logs, route tới backends |
| **Prometheus** | 9090 | Metrics storage, PromQL, recording rules, alerting rules |
| **Grafana** | 3000 | Dashboards — application health, Kafka, workers, SLO |
| **Tempo** | 3200 | Distributed tracing backend |
| **Loki** | 3100 | Log aggregation với LogQL |
| **Alertmanager** | 9093 | Alert routing → Telegram |
| **Blackbox Exporter** | 9115 | Active probing — health endpoint monitoring |
| **MinIO** | 9000 | S3-compatible storage backend cho Loki/Tempo |

### Design Patterns

| Pattern | Mô tả |
|---------|-------|
| **Event-Driven Architecture** | Order Service publish events → Kafka → Workers consume độc lập |
| **Idempotent Processing** | `processed_events` table prevent duplicate processing khi Kafka redeliver |
| **Cache-Aside (Redis)** | Check cache → miss → query DB → populate cache (TTL 60s) |
| **Pessimistic Locking** | `SELECT ... FOR UPDATE` khi update stock, tránh race condition |
| **Distributed Trace Propagation** | W3C TraceContext inject/extract qua Kafka message headers |
| **BFF (Backend for Frontend)** | API Gateway aggregates backend calls cho Web UI |
| **RFC 7807 Problem Details** | Chuẩn hóa error response format cho tất cả services |

### Lộ Trình Thực Hành

| Giai đoạn | Tài liệu | Kỹ năng trọng tâm | Độ khó |
|-----------|----------|-------------------|--------|
| **Phase 1-3** | `observability-vm/phase{1,2,3}/` | Deploy stack, cấu hình OTel pipeline, dashboard cơ bản | ⭐ |
| **Phase 4-5** | `applications-vm/` + `ARCHITECTURE.md` | Microservices communication, DB/Kafka internals, caching | ⭐⭐ |
| **Incident Drill** | `INCIDENT_SIMULATION_GUIDE.md` + `INCIDENT_RUNBOOK.md` | Triage, SEV assessment, Escalation, Dashboard reading | ⭐⭐⭐ |
| **Deep Internals** | `BREAK_TEST_RECOVERY.md` | Phá & khôi phục PostgreSQL, Kafka, Redis, Prometheus | ⭐⭐⭐ |
| **Post-Mortem** | `post-mortems/` | Viết Blameless RCA, 5 Whys, Action Items trackable | ⭐⭐ |
| **Scale & Evolution** | `EXPANSION_PLAN.md` | Saga, CQRS, Circuit Breaker, TLS, Network Segmentation | ⭐⭐⭐⭐ |

---

## ☁️ Terraform — AWS

> 📖 **Hướng dẫn chi tiết:** xem [`terraform/README.md`](terraform/README.md)

### Modules đã triển khai

| Module | Mô tả | Trạng thái |
|--------|-------|-----------|
| `network` | VPC 3-tier (public/private/data) × 3 AZs, NAT Gateway, Route Tables | ✅ Done |
| `security` | Security Groups, IAM roles, least-privilege policies | ✅ Done |
| `database` | RDS PostgreSQL Multi-AZ, encrypted, auto backup | ✅ Done |
| `vpc-endpoints` | Private connectivity tới S3, ECR, SSM, Secrets Manager | ✅ Done |
| `logging-flow-logs` | S3 flow log archive + Athena query + KMS encryption | ✅ Done |
| `backup` | AWS Backup vault, plans, cross-region copy, compliance reports | ✅ Done |
| `cache` | ElastiCache Replication Group | 🔲 TODO |
| `streaming` | MSK Cluster (Multi-AZ) | 🔲 TODO |
| Compute (ECS/EKS) | 4 phases: EC2 → Fargate → EKS NodeGroup → EKS Fargate | 🔲 TODO |

### Policy-as-Code (OPA/Rego)

Terraform plans được validate tự động bằng **14 OPA policies**:

- **Network** — Không cho phép `0.0.0.0/0` ingress trên non-public resources
- **RDS** — Enforce encryption, multi-AZ, backup retention
- **IAM** — Kiểm tra least-privilege, không cho `*` permissions
- **Security Groups** — Validate port ranges, CIDR blocks
- **KMS/S3/Secrets** — Encryption và access control checks
- **Backup** — Enforce vault lock, retention policies
- **VPC Endpoints** — Validate private connectivity
- **Logging** — Enforce flow log configuration

### So sánh On-Prem vs AWS

| Aspect | On-Prem (Docker Compose) | AWS (Terraform) |
|--------|--------------------------|----------------|
| Network | Single bridge network | VPC + Subnets + NAT + SGs + NACLs |
| Compute | `docker compose up` | ECS/EKS + ASG + Capacity Providers |
| Database | PostgreSQL container | RDS Multi-AZ + RDS Proxy |
| Cache | Redis container | ElastiCache Replication Group |
| Streaming | Kafka KRaft single broker | MSK Cluster (Multi-AZ) |
| Secrets | `.env` files | Secrets Manager + KMS |
| CI/CD Auth | N/A | OIDC + IAM Roles |
| Chaos | `docker stop <container>` | AWS FIS (AZ failure, network partition) |
| DR | Backup files | Cross-region RDS replica + Route53 failover |
| Cost | Fixed (hardware) | Variable ($/hour) — FinOps critical |

---

## ⚙️ CI/CD Pipeline

Repository sử dụng **GitHub Actions** với reusable workflows:

| Workflow | Chức năng |
|----------|----------|
| `ci.yml` | Main CI — lint, test, build Docker images |
| `ci-api-gateway.yml` | CI riêng cho API Gateway service |
| `terraform-policy.yml` | Validate Terraform plans với OPA policies |
| `terraform-drift.yml` | Nightly drift detection + Slack/Telegram alerts |
| `_reusable-build-push.yml` | Reusable workflow: Docker build & push (ECR + GHCR) |
| `_reusable-lint-test.yml` | Reusable workflow: linting + testing |

---

## 🚀 Hướng Dẫn Bắt Đầu

### On-Premises (Docker Compose)

**Yêu cầu:**
- Docker ≥ 24.0 & Docker Compose ≥ 2.20
- 2 VMs (hoặc 1 máy đủ RAM): Applications VM (≥ 8GB RAM), Observability VM (≥ 4GB RAM)

```bash
# 1. Clone repository
git clone <repo-url>
cd observability-sample-v2

# 2. Tạo Docker network
docker network create observability

# 3. Khởi động Storage Layer (MinIO) — trên Observability VM
cd on-premises/observability-vm/storage
docker compose up -d

# 4. Khởi động Observability Stack (Phase 1 → 2 → 3)
cd ../phase1-metrics && docker compose up -d
cd ../phase2-logging && docker compose up -d
cd ../phase3-tracing && docker compose up -d

# 5. Khởi động Monitoring Agents — trên Applications VM
cd ../../applications-vm/agents
docker compose up -d

# 6. Khởi động Application Services
cd ../applications
docker compose up -d

# 7. Verify
curl -s http://localhost:5000/health | jq .
```

> ⚠️ **Thứ tự khởi động quan trọng:** MinIO → Observability Stack → Agents → Applications. Loki/Tempo phụ thuộc MinIO, Applications phụ thuộc OTel Collector.

### Terraform (AWS)

**Yêu cầu:**
- Terraform ≥ 1.7.0, AWS CLI configured, OPA + conftest installed

```bash
# 1. Bootstrap S3 state backend
cd terraform/bootstrap
terraform init && terraform apply

# 2. Deploy shared infrastructure
cd ../environments/shared
terraform init
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
conftest test plan.json -p ../../policy/    # Validate OPA policies
terraform apply plan.tfplan
```

> 💡 **FinOps Tip:** `terraform destroy` → $0/day. Apply sáng, destroy tối ≈ $10/ngày.

### Truy cập

| Giao diện | URL |
|-----------|-----|
| Web UI | `http://<APP_VM_IP>:8580` |
| Kafka UI | `http://<APP_VM_IP>:8585` |
| Grafana | `http://<OBS_VM_IP>:3000` |
| Prometheus | `http://<OBS_VM_IP>:9090` |

---

## 📚 Tài Liệu Tham Khảo

### On-Premises

| File | Nội dung |
|------|---------|
| [`ARCHITECTURE.md`](on-premises/ARCHITECTURE.md) | Kiến trúc chi tiết — services, data flow, DB schema, design patterns |
| [`EXPANSION_PLAN.md`](on-premises/EXPANSION_PLAN.md) | Roadmap mở rộng 6 → 10 services — Saga, CQRS, Circuit Breaking, TLS |
| [`INCIDENT_SIMULATION_GUIDE.md`](on-premises/INCIDENT_SIMULATION_GUIDE.md) | 12 chaos experiments — DB lock, Kafka lag, phantom alerts, cascading failure |
| [`INCIDENT_RUNBOOK.md`](on-premises/INCIDENT_RUNBOOK.md) | 24 incident runbooks — SEV matrix, escalation, recovery procedures |
| [`BREAK_TEST_RECOVERY.md`](on-premises/BREAK_TEST_RECOVERY.md) | 28 break/test/recovery drills — PostgreSQL, Kafka, Redis, Prometheus internals |
| [`post-mortems/`](on-premises/post-mortems/) | Blameless Post-Mortem templates & golden example (DB Saturation) |
| [`devops-question.md`](on-premises/devops-question.md) | DevOps interview — junior/mid (45 câu) |
| [`devops-question-senior.md`](on-premises/devops-question-senior.md) | DevOps interview — senior/staff (31 câu) |

### Terraform / AWS

| File | Nội dung |
|------|---------|
| [`ARCHITECTURE.md`](terraform/ARCHITECTURE.md) | AWS blueprint — VPC topology, compute phases, failure domains |
| [`AWS_TERRAFORM_PLAYBOOK.md`](terraform/AWS_TERRAFORM_PLAYBOOK.md) | Module-by-module deployment playbook |
| [`docs/TRADE_OFFS.md`](terraform/docs/TRADE_OFFS.md) | Architecture decision records — why these AWS services? |
| [`docs/FINOPS.md`](terraform/docs/FINOPS.md) | AWS cost management & optimization strategies |
| [`docs/chaos-exercises-network.md`](terraform/docs/chaos-exercises-network.md) | 12 network chaos engineering exercises |
| [`policy/README.md`](terraform/policy/README.md) | Hướng dẫn OPA policy-as-code |
| [`interviews/devops-question-m1-iac-core.md`](terraform/interviews/devops-question-m1-iac-core.md) | 54 câu hỏi phỏng vấn IaC (Terraform, state, modules) |

### Công nghệ sử dụng

| Lĩnh vực | Công nghệ |
|----------|----------|
| **Backend** | Python 3.11+ (Flask), Gunicorn, Nginx |
| **Database** | PostgreSQL 16, Redis 7 |
| **Messaging** | Apache Kafka 3.7 (KRaft mode — no ZooKeeper) |
| **Observability** | OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Alertmanager, Blackbox Exporter |
| **Storage** | MinIO (S3-compatible backend cho Loki/Tempo) |
| **Infrastructure** | Docker Compose, Terraform, AWS (VPC, RDS, Security Groups, KMS) |
| **Policy** | OPA / Rego (Conftest) — 14 policy files + unit tests |
| **CI/CD** | GitHub Actions (reusable workflows, OIDC) |

---

*Dự án được phát triển như một production-grade learning lab cho DevOps, SRE và Cloud Engineering. Mọi đóng góp và phản hồi đều được hoan nghênh!*

> 🛡️ *"Reliability is the most important feature. If users can't access the system, nothing else matters."* — Google SRE Book
