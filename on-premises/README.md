# 🖥️ On-Premises — Production-Grade Observability & Reliability Lab

> **Không phải toy project.** Đây là sandbox được thiết kế để rèn luyện tư duy System Design và SRE ở tiêu chuẩn production.  
> Hệ thống E-commerce Microservices với full-stack observability (Metrics, Logs, Traces) và Incident Management chạy trên 2 VMs bằng Docker Compose.

---

## 🧠 Core Engineering & SRE Concepts

Dự án này không chỉ là "deploy code lên Docker", mà là nơi thực hành các patterns và concepts thực tế mà các Senior/Staff Engineer phải đối mặt:

| Khía cạnh | Concepts & Patterns được áp dụng |
|---|---|
| **System Design** | Event-Driven Architecture (Kafka KRaft), Cache-Aside (Redis), Pessimistic Locking (`SELECT FOR UPDATE`), BFF Pattern, Idempotency. |
| **Reliability (SRE)** | SLI/SLO & Error Budgets, Multi-Window Multi-Burn-Rate (MWMBR) Alerting, Traffic Guards (chống Phantom Alerts), Active Probing (Blackbox). |
| **Observability** | 3 Pillars + Correlation (TraceID trong Logs/Metrics), Tail-based Sampling, Auto RED Metrics (Spanmetrics Connector), Structured JSON Logging. |
| **Incident Mgmt** | 12 Chaos Experiments, 24 Alert Runbooks, Blameless Post-Mortems, Break/Test/Recovery Drills. |
| **Security & Ops** | Multi-stage Docker builds, Non-root users, Read-only filesystems, Network segmentation, Graceful shutdown (SIGTERM). |

---

## 🏗️ Kiến Trúc Hệ Thống

Hệ thống gồm **2 VMs** giao tiếp qua Docker external network, tách biệt hoàn toàn giữa Business Logic và Monitoring Stack (mô phỏng production environment).

```text
┌───────────────────────────────────────────────────────────────────┐
│                      Applications VM (60GB RAM)                   │
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
│                     Observability VM (32GB RAM)                   │
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

> Xem chi tiết Data Flows, DB Schema và Design Patterns tại: [ARCHITECTURE.md](ARCHITECTURE.md)

---
## 🗺️ Blueprint & Evolution Roadmap

Một hệ thống production-grade không chỉ dừng lại ở hiện tại. Repository này cung cấp đầy đủ tài liệu về trạng thái hiện tại (As-Is) và lộ trình tiến hóa (To-Be) để phục vụ cho cả Software Architect và SRE Team:

| Tài liệu | Vai trò | Dành cho ai? |
|----------|---------|--------------|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | **As-Is Blueprint:** Sơ đồ Data Flow, DB Schema, Kafka Topics, và các Design Patterns đang áp dụng (Cache-Aside, Pessimistic Locking, Idempotency). | Devs, SREs, PMs cần hiểu luồng đi của dữ liệu và các điểm gãy (failure points) hiện tại. |
| **[EXPANSION_PLAN.md](EXPANSION_PLAN.md)** | **To-Be Roadmap:** Kế hoạch scale từ 6 lên 10 services. Giới thiệu các pattern enterprise: **Saga Orchestration**, **CQRS**, **Circuit Breaker**, **TLS**, **Network Segmentation**. | Architects thiết kế giải pháp. **SREs đọc để chuẩn bị trước Observability & Chaos Engineering strategy** cho các failure domains mới (VD: Saga compensation, CQRS sync lag). |

> 💡 **Reliability PM Note:** *Đừng đợi code viết xong mới nghĩ đến monitoring. Hãy đọc `EXPANSION_PLAN.md` để định nghĩa SLI/SLO và thiết kế Runbook cho các service sắp ra mắt (Auth, Shipping, Search) ngay từ giai đoạn thiết kế.*

---
## 🚀 Quick Start (Boot Sequence)

> ⚠️ **Lưu ý:** Thứ tự khởi động rất quan trọng. Loki và Tempo phụ thuộc vào MinIO (S3), và Applications phụ thuộc vào OTel Collector.

### Prerequisites

- Docker Engine ≥ 24.0 & Docker Compose ≥ 2.20
- 2 VMs (hoặc 1 VM đủ RAM) có network connectivity.

### 1. Tạo external network

```bash
docker network create observability
```

### 2. Khởi động Storage Layer (MinIO)

```bash
cd observability-vm/storage
docker compose up -d
cd ../..
```

### 3. Khởi động Observability Stack (Phase 1 → 2 → 3)

```bash
# Phase 1: Metrics & Alerting
cd observability-vm/phase1-metrics
docker compose up -d
cd ..

# Phase 2: Logging
cd phase2-logging
docker compose up -d
cd ..

# Phase 3: Tracing
cd phase3-tracing
docker compose up -d
cd ../..
```

### 4. Khởi động Monitoring Agents (trên App VM)

```bash
cd applications-vm/agents
docker compose up -d
cd ../..
```

### 5. Khởi động Applications

```bash
cd applications-vm/applications
docker compose up -d
```

### 🌐 Truy cập

| Service | URL | Mô tả |
|---|---|---|
| **Web UI** | `http://<app-vm>:8580` | E-commerce frontend & Load Test Control |
| **Grafana** | `http://<obs-vm>:3000` | Dashboards (admin/admin123) |
| **Kafka UI** | `http://<app-vm>:8585` | Kafka topics & consumers |
| **Prometheus** | `http://<obs-vm>:9090` | Metrics queries & Rules |

---

## 📚 Learning Roadmap (6 Phases)

Dự án được chia thành 6 phases, đi từ cơ bản đến nâng cao theo tiêu chuẩn SRE:

| Phase | Chủ đề | Level | Trạng thái |
|---|---|---|---|
| **Phase 1** | Metrics & Alerting — Prometheus, MWMBR Alerts, Blackbox | Cơ bản | ✅ |
| **Phase 2** | Logging — Loki, Alloy Pipeline, Structured JSON | Cơ bản | ✅ |
| **Phase 3** | Tracing — Tempo, OTel Collector, Tail-based Sampling | Trung cấp | ✅ |
| **Phase 4** | SLO & Correlation — Error Budgets, Log→Trace linking | Nâng cao | ✅ |
| **Phase 5** | App Instrumentation — Custom Metrics, RFC 7807 Errors | Nâng cao | ✅ |
| **Phase 6** | Incident Mgmt — Chaos Simulations, Post-Mortems | Expert | ✅ |

---

## 🛠️ Thực hành Incident & Chaos Engineering

Đây là phần "đắt giá" nhất của repository, giúp bạn rèn luyện phản xạ của một On-call Engineer:

| Tài liệu | Nội dung | Mục tiêu |
|---|---|---|
| [INCIDENT_SIMULATION_GUIDE.md](INCIDENT_SIMULATION_GUIDE.md) | 12 Experiments giả lập sự cố (DB Lock, Kafka Lag, Phantom Alerts...) | Luyện đọc Dashboard, Incident Flow, Triage. |
| [INCIDENT_RUNBOOK.md](INCIDENT_RUNBOOK.md) | Runbook xử lý cho 24 loại alert | Chuẩn hóa quy trình phản ứng (SEV Assessment, Escalation). |
| [BREAK_TEST_RECOVERY.md](BREAK_TEST_RECOVERY.md) | 28 bài thực hành Break/Test/Recovery | Hiểu sâu internals của Postgres, Kafka, Redis, Prometheus. |
| [post-mortems/](post-mortems/) | Template & Golden Example Post-Mortem | Luyện viết Blameless Post-Mortem, 5 Whys. |

---

## 📂 Cấu Trúc Thư Mục

```text
on-premises/
├── README.md                          ← File này
├── ARCHITECTURE.md                    ← Kiến trúc, Data Flows, DB Schema
├── EXPANSION_PLAN.md                  ← Kế hoạch scale lên 10 services (Saga, CQRS)
├── INCIDENT_SIMULATION_GUIDE.md       ← 12 Chaos Experiments
├── INCIDENT_RUNBOOK.md                ← 24 Alert Runbooks
├── BREAK_TEST_RECOVERY.md             ← Component Deep-dive Drills
├── devops-question.md                 ← 45 Câu hỏi phỏng vấn (Junior-Mid)
├── devops-question-senior.md          ← 31 Câu hỏi phỏng vấn (Senior/Staff)
│
├── applications-vm/
│   ├── applications/                  # Source code Microservices (Python/Flask)
│   │   ├── api-gateway/               # BFF, Rate Limit, JWT
│   │   ├── order-service/             # Core logic, Cache-aside, Kafka Producer
│   │   ├── payment-service/           # Simulated latency/errors
│   │   ├── inventory-worker/          # Kafka Consumer, Pessimistic Lock
│   │   ├── notification-worker/       # Kafka Consumer, Idempotency
│   │   ├── traffic-gen/               # API-controlled Load Testing
│   │   ├── web-ui/                    # Nginx SPA
│   │   └── shared/                    # OTel setup, DB pools, Health checks
│   └── agents/                        # Grafana Alloy (Log collection)
│
├── observability-vm/
│   ├── storage/                       # MinIO (S3 backend)
│   ├── phase1-metrics/                # Prometheus, Alertmanager, Blackbox
│   ├── phase2-logging/                # Loki, Alloy
│   ├── phase3-tracing/                # Tempo, OTel Collector
│   └── scripts/                       # annotate.sh, deploy.sh
│
└── post-mortems/                      # Blameless Post-Mortem Templates
```

---

## 📝 DevOps / SRE Interview Practice

Bộ câu hỏi phỏng vấn được thiết kế riêng dựa trên chính codebase này, yêu cầu giải thích **"Why"** và **"Trade-offs"** chứ không chỉ "What":

| File | Level | Số câu | Focus Areas |
|---|---|---|---|
| [devops-question.md](devops-question.md) | Junior–Mid | 45 | Docker, Networking, Kafka, Observability, SLO, CI/CD, Troubleshooting |
| [devops-question-senior.md](devops-question-senior.md) | Senior/Staff | 31 | Architecture Design, SLO Strategy, Chaos Engineering, Platform Eng, Leadership |

---

## 🔗 Liên Quan (AWS / Cloud)

Repository này tập trung vào On-Premises / Docker Compose để hiểu sâu bản chất.  
Để xem cách hệ thống này được triển khai lên Cloud với Terraform, EKS, ECS và CI/CD GitOps, vui lòng tham khảo:

- [../README.md](../README.md) — Tổng quan toàn bộ dự án
- [../terraform/](../terraform/) — AWS Infrastructure as Code (Terraform)
- [../terraform/devops-question-m1-iac-core.md](../terraform/devops-question-m1-iac-core.md) — DevOps Interview cho Terraform/AWS