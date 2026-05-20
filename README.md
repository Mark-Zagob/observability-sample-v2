# 🔭 Observability Lab — E-Commerce Microservices

> Dự án học tập về **Observability** và **DevOps** thông qua việc xây dựng hệ thống e-commerce microservices hoàn chỉnh, với full-stack monitoring (Metrics, Logs, Traces) và infrastructure-as-code trên AWS.

---

## 📋 Mục Lục

- [Tổng Quan](#-tổng-quan)
- [Kiến Trúc Hệ Thống](#-kiến-trúc-hệ-thống)
- [Cấu Trúc Repository](#-cấu-trúc-repository)
- [On-Premises (Docker Compose)](#-on-premises--docker-compose)
- [Terraform — AWS (🚧 Đang phát triển)](#-terraform--aws--đang-phát-triển)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Hướng Dẫn Bắt Đầu](#-hướng-dẫn-bắt-đầu)
- [Kiến Thức Tham Khảo](#-kiến-thức-tham-khảo)

---

## 🎯 Tổng Quan

Dự án này bao gồm **hai phần chính**:

| Phần | Trạng thái | Mô tả |
|------|-----------|-------|
| **On-Premises** (Docker Compose) | 🔄 Phase 1 hoàn tất | 6 microservices + full observability stack trên 2 VMs. [Expansion Plan](on-premises/EXPANSION_PLAN.md) lên 10 services đang triển khai |
| **Terraform — AWS** | 🚧 Đang phát triển | Infrastructure-as-code để deploy hệ thống lên AWS (VPC, RDS, Security, Policy-as-Code) |

### Bạn sẽ học được gì?

- **Microservices Architecture** — Event-driven (Kafka), sync HTTP, BFF pattern
- **Observability 3 trụ cột** — Metrics (Prometheus), Logs (Loki), Traces (Tempo)
- **Distributed Tracing** — Trace propagation qua Kafka message headers (W3C TraceContext)
- **Alerting & Notification** — Alertmanager → Telegram, predictive alerting (`predict_linear()`)
- **Application Instrumentation** — Custom metrics (Counter, Histogram), manual spans, structured logging
- **Infrastructure-as-Code** — Terraform modules, OPA policy-as-code, CI/CD với GitHub Actions
- **Design Patterns** — Idempotency, Cache-Aside, Pessimistic Locking, Event Sourcing

---

## 🏗️ Kiến Trúc Hệ Thống

### On-Premises — 2 VMs, Docker Compose

```
┌─────────────────────────────────────────────────────┐
│              Applications VM                         │
│                                                      │
│  Web UI (nginx) → API Gateway → Order Service        │
│                                    ↕     ↕     ↕     │
│                              PostgreSQL Redis Kafka   │
│                                              ↕       │
│                              Notification  Inventory  │
│                                Worker       Worker    │
│  Payment Service    Traffic Generator    Kafka UI     │
└────────────────────────┬────────────────────────────┘
                         │ OTLP (gRPC :4317)
┌────────────────────────▼────────────────────────────┐
│              Observability VM                        │
│                                                      │
│  OTel Collector → Prometheus → Grafana               │
│                 → Tempo     ↗                        │
│                 → Loki    ↗                          │
│                   Alertmanager → Telegram             │
└──────────────────────────────────────────────────────┘
```

> 📖 Chi tiết kiến trúc: xem [`on-premises/ARCHITECTURE.md`](on-premises/ARCHITECTURE.md)

### AWS — Production-Grade (Terraform)

```
Internet → Route53 → WAF → ALB → Compute (ECS/EKS) → RDS + ElastiCache + MSK
                                                     → Observability Stack
```

> 📖 Chi tiết AWS: xem [`terraform/ARCHITECTURE.md`](terraform/ARCHITECTURE.md)

---

## 📁 Cấu Trúc Repository

```
observability-sample-v2/
│
├── on-premises/                          # 🔄 Docker Compose — Phase 1 done
│   ├── ARCHITECTURE.md                   # Kiến trúc, data flows, DB schema, design patterns
│   ├── EXPANSION_PLAN.md                 # Roadmap mở rộng 6 → 10 services (Saga, CQRS, Circuit Breaking)
│   ├── INCIDENT_RUNBOOK.md               # 22 runbooks cho tất cả alert rules
│   ├── OBSERVABILITY_LEARNING_GUIDE.md   # 7 chaos experiments + hands-on exercises
│   ├── devops-question.md                # DevOps interview practice (junior/mid)
│   ├── devops-question-senior.md         # DevOps interview practice (senior)
│   │
│   ├── applications-vm/                  # VM chạy ứng dụng
│   │   └── applications/
│   │       ├── docker-compose.yml        # 11-service orchestration
│   │       ├── init.sql                  # Database schema + seed data
│   │       ├── api-gateway/              # BFF routing (Flask :5000)
│   │       ├── order-service/            # Core business logic + Kafka producer
│   │       ├── payment-service/          # Simulated payment (Flask :5002)
│   │       ├── notification-worker/      # Kafka consumer → notifications
│   │       ├── inventory-worker/         # Kafka consumer → stock management
│   │       ├── traffic-gen/              # Load testing tool
│   │       ├── web-ui/                   # Nginx SPA dashboard
│   │       └── sample-app/              # Reference instrumented app
│   │
│   └── observability-vm/                 # VM chạy monitoring stack
│       ├── phase1-metrics/               # Prometheus, Grafana, Recording Rules
│       ├── phase2-logging/               # Loki, structured JSON logging
│       └── phase3-tracing/               # Tempo, OTel Collector
│
├── terraform/                            # ☁️ AWS IaC
│   ├── ARCHITECTURE.md                  # Kiến trúc AWS (Mermaid diagrams)
│   ├── IMPLEMENTATION_PLAN.md           # Kế hoạch triển khai chi tiết
│   ├── chaos-exercises-network.md       # Chaos engineering exercises
│   ├── devops-question-m1-iac-core.md   # DevOps interview practice
│   ├── bootstrap/                       # S3 state backend (native lockfile)
│   ├── environments/
│   │   ├── shared/                      # Shared infra (VPC, security, RDS)
│   │   └── dev/                         # Dev environment
│   ├── modules/
│   │   ├── network/                     # VPC, subnets, NAT, route tables
│   │   ├── security/                    # Security groups, IAM
│   │   ├── database/                    # RDS PostgreSQL
│   │   ├── vpc-endpoints/               # Private connectivity tới AWS services
│   │   ├── logging-flow-logs/           # S3 + Athena for flow log archive
│   │   └── backup/                      # AWS Backup vault, plans, reports
│   └── policy/                          # OPA/Rego policy-as-code
│       ├── general.rego                 # General Terraform policies
│       ├── network.rego                 # Network security rules
│       ├── rds.rego                     # Database hardening rules
│       ├── security_group.rego          # SG validation
│       ├── iam.rego                     # IAM least-privilege checks
│       └── tests/                       # Policy unit tests
│
└── .github/workflows/                   # CI/CD Pipelines
    ├── ci.yml                           # Main CI pipeline
    ├── ci-api-gateway.yml               # API Gateway CI
    ├── terraform-policy.yml             # Terraform policy validation
    ├── terraform-drift.yml              # Nightly drift detection + Slack/Telegram alerts
    ├── _reusable-build-push.yml         # Reusable: Docker build & push
    └── _reusable-lint-test.yml          # Reusable: lint + test
```

---

## 🐳 On-Premises — Docker Compose

### Services

#### Application Services

| Service | Port | Tech | Vai trò |
|---------|------|------|---------|
| **Web UI** | 8580 | Nginx | SPA dashboard — orders, events, load testing |
| **API Gateway** | 5000 | Flask | BFF pattern — routing, aggregation, error propagation |
| **Order Service** | 5001 | Flask | Tạo order, gọi payment, publish Kafka events |
| **Payment Service** | 5002 | Flask | Simulated payment (configurable latency/errors) |
| **Notification Worker** | 5004 | Flask | Kafka consumer → xử lý notifications |
| **Inventory Worker** | 5005 | Flask | Kafka consumer → quản lý stock (pessimistic locking) |
| **Traffic Generator** | 5003 | Flask | Load testing với scenario templates |

#### Infrastructure Services

| Service | Port | Vai trò |
|---------|------|---------|
| **PostgreSQL 16** | 5432 | Database chính — orders, products, notifications, inventory |
| **Redis 7** | 6379 | Cache layer — product catalog (TTL 60s) |
| **Kafka 3.7 (KRaft)** | 9092 | Event streaming — không cần ZooKeeper |
| **Kafka UI** | 8585 | Web UI cho topic/consumer inspection |

#### Observability Stack (VM riêng)

| Tool | Port | Vai trò |
|------|------|---------|
| **OTel Collector** | 4317/4318 | Thu nhận OTLP traces/metrics/logs, route tới backends |
| **Prometheus** | 9090 | Metrics storage, PromQL, recording rules, alerting rules |
| **Grafana** | 3000 | Dashboards — application health, Kafka, workers |
| **Tempo** | 3200 | Distributed tracing backend |
| **Loki** | 3100 | Log aggregation với LogQL |
| **Alertmanager** | 9093 | Alert routing → Telegram |

### Lộ Trình Học Observability (6 Phases + Chaos Experiments)

| Phase | Chủ đề | Nội dung chính |
|-------|--------|---------------|
| **1** | Metrics Foundation | Prometheus, Grafana, Node Exporter, cAdvisor |
| **2** | Logging | Loki, structured JSON logging, LogQL |
| **3** | Distributed Tracing | Tempo, OTel Collector, trace-to-log correlation |
| **4** | Alerting | Alertmanager, Recording Rules, Telegram, `predict_linear()` |
| **5** | App Instrumentation | Custom metrics (Counter, Histogram), manual spans, OTel SDK |
| **6** | Correlation & SLO | Metrics↔Logs↔Traces correlation, SLI/SLO monitoring |

> 📖 Sau khi hoàn thành 6 phases, tiếp tục với [**7 Chaos Experiments**](on-premises/OBSERVABILITY_LEARNING_GUIDE.md)
> để thực hành incident triage: DB saturation, cascading failure, Kafka consumer lag, SLO burn rate analysis.

### Design Patterns

| Pattern | Mô tả |
|---------|-------|
| **Event-Driven Architecture** | Order Service publish events → Kafka → Workers consume độc lập |
| **Idempotent Processing** | `processed_events` table prevent duplicate processing khi Kafka redeliver |
| **Cache-Aside (Redis)** | Check cache → miss → query DB → populate cache (TTL 60s) |
| **Pessimistic Locking** | `SELECT ... FOR UPDATE` khi update stock, tránh race condition |
| **Distributed Trace Propagation** | W3C TraceContext inject/extract qua Kafka message headers |
| **BFF (Backend for Frontend)** | API Gateway aggregates backend calls cho Web UI |

---

## ☁️ Terraform — AWS (🚧 Đang phát triển)

> [!WARNING]
> Phần Terraform AWS đang trong quá trình phát triển, chưa hoàn tất. Bạn có thể tham khảo code và kiến trúc nhưng chưa nên dùng cho production.

### Modules đã triển khai

| Module | Mô tả | Trạng thái |
|--------|-------|-----------|
| `network` | VPC 3-tier (public/private/data) × 3 AZs, NAT Gateway, Route Tables | ✅ |
| `security` | Security Groups, IAM roles, least-privilege policies | ✅ |
| `database` | RDS PostgreSQL Multi-AZ, encrypted, auto backup | ✅ |
| `vpc-endpoints` | Private connectivity tới S3, ECR, SSM, Secrets Manager | ✅ |
| `logging-flow-logs` | S3 flow log archive + Athena query + KMS encryption | ✅ |
| `backup` | AWS Backup vault, plans, cross-region copy, compliance reports | ✅ |

### Policy-as-Code (OPA/Rego)

Terraform plans được validate tự động bằng OPA policies:

- **Network** — Không cho phép `0.0.0.0/0` ingress trên non-public resources
- **RDS** — Enforce encryption, multi-AZ, backup retention
- **IAM** — Kiểm tra least-privilege, không cho `*` permissions
- **Security Groups** — Validate port ranges, CIDR blocks
- **KMS/S3/Secrets** — Encryption và access control checks

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

### Yêu cầu

- Docker & Docker Compose
- 2 VMs (hoặc 1 máy đủ RAM):
  - **Applications VM**: ≥ 8GB RAM khuyến nghị
  - **Observability VM**: ≥ 4GB RAM khuyến nghị

### Chạy ứng dụng

```bash
# 1. Clone repository
git clone <repo-url>
cd observability-sample-v2

# 2. Tạo Docker network
docker network create observability

# 3. Khởi động application services
cd on-premises/applications-vm/applications
docker compose up -d --build

# 4. Kiểm tra trạng thái
docker compose ps
```

### Chạy observability stack

```bash
# Trên Observability VM (hoặc cùng máy)

# Phase 1 — Metrics
cd on-premises/observability-vm/phase1-metrics
docker compose up -d

# Phase 2 — Logging
cd ../phase2-logging
docker compose up -d

# Phase 3 — Tracing
cd ../phase3-tracing
docker compose up -d
```

### Truy cập

| Giao diện | URL |
|-----------|-----|
| Web UI | `http://<APP_VM_IP>:8580` |
| Kafka UI | `http://<APP_VM_IP>:8585` |
| Grafana | `http://<OBS_VM_IP>:3000` |
| Prometheus | `http://<OBS_VM_IP>:9090` |

---

## 📚 Kiến Thức Tham Khảo

### Tài liệu trong repo

**On-Premises:**

| File | Nội dung |
|------|---------|
| [`on-premises/ARCHITECTURE.md`](on-premises/ARCHITECTURE.md) | Kiến trúc chi tiết — services, data flow, DB schema, design patterns |
| [`on-premises/EXPANSION_PLAN.md`](on-premises/EXPANSION_PLAN.md) | Roadmap mở rộng 6 → 10 services — Saga, CQRS, Circuit Breaking, TLS, CI/CD |
| [`on-premises/INCIDENT_RUNBOOK.md`](on-premises/INCIDENT_RUNBOOK.md) | 22 incident runbooks — SEV1-4 severity, escalation matrix, recovery procedures |
| [`on-premises/OBSERVABILITY_LEARNING_GUIDE.md`](on-premises/OBSERVABILITY_LEARNING_GUIDE.md) | 7 chaos experiments — DB saturation, cascading failure, Kafka lag, SLO burn rate |
| [`on-premises/devops-question.md`](on-premises/devops-question.md) | DevOps interview practice — junior/mid level |
| [`on-premises/devops-question-senior.md`](on-premises/devops-question-senior.md) | DevOps interview practice — senior level |

**Terraform / AWS:**

| File | Nội dung |
|------|---------|
| [`terraform/ARCHITECTURE.md`](terraform/ARCHITECTURE.md) | Kiến trúc AWS — VPC topology, compute phases, security flow |
| [`terraform/IMPLEMENTATION_PLAN.md`](terraform/IMPLEMENTATION_PLAN.md) | Kế hoạch triển khai Terraform chi tiết |
| [`terraform/chaos-exercises-network.md`](terraform/chaos-exercises-network.md) | Chaos engineering — 12 break/test/recover exercises |
| [`terraform/devops-question-m1-iac-core.md`](terraform/devops-question-m1-iac-core.md) | DevOps interview practice — 54 câu hỏi IaC |
| [`terraform/policy/README.md`](terraform/policy/README.md) | Hướng dẫn OPA policy-as-code |

### Công nghệ sử dụng

| Lĩnh vực | Công nghệ |
|----------|----------|
| **Backend** | Python (Flask), Nginx |
| **Database** | PostgreSQL 16, Redis 7 |
| **Messaging** | Apache Kafka 3.7 (KRaft mode) |
| **Observability** | OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Alertmanager |
| **Infrastructure** | Docker Compose, Terraform, AWS (VPC, RDS, Security Groups) |
| **Policy** | OPA / Rego (Conftest) |
| **CI/CD** | GitHub Actions |

---

*Dự án được phát triển như một learning lab cho DevOps và Observability. Mọi đóng góp và phản hồi đều được hoan nghênh!*
