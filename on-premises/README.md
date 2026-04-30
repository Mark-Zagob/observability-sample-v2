# 🖥️ On-Premises — Docker Compose Observability Lab

> E-commerce microservices với full-stack observability (Metrics, Logs, Traces) chạy trên 2 VMs bằng Docker Compose.

---

## 📋 Tổng Quan

Hệ thống gồm **2 VMs** giao tiếp qua Docker external network:

| VM | RAM | Vai trò | Services |
|----|-----|---------|----------|
| **Applications VM** | 60GB | Business logic + Data layer | Web UI, API Gateway, Order Service, Payment Service, Workers, PostgreSQL, Redis, Kafka |
| **Observability VM** | 32GB | Monitoring stack | OTel Collector, Prometheus, Grafana, Tempo, Loki, Alertmanager |

### Tech Stack

- **Application**: Python (Flask), Node.js (Express)
- **Data**: PostgreSQL 16, Redis 7, Kafka 3.7 (KRaft mode)
- **Observability**: OpenTelemetry Collector, Prometheus, Grafana, Tempo, Loki, Alertmanager
- **Infrastructure**: Docker Compose, nginx reverse proxy
- **Alerting**: Alertmanager → Telegram webhook

---

## 🏗️ Kiến Trúc

Xem chi tiết tại:
- [ARCHITECTURE.md](ARCHITECTURE.md) — Sơ đồ Mermaid
- [ARCHITECTURE_DETAIL.md](ARCHITECTURE_DETAIL.md) — Giải thích chi tiết từng component
- [architecture_summary.md](architecture_summary.md) — Tổng kết kiến trúc và kiến thức DevOps

```
┌─────────────────────────────────────────────────┐
│              Applications VM                     │
│                                                  │
│  Web UI (nginx) → API Gateway → Order Service    │
│                                  ↕     ↕     ↕   │
│                            PostgreSQL Redis Kafka │
│                                            ↕     │
│                           Notification  Inventory │
│                             Worker       Worker   │
│  Payment Service    Traffic Generator             │
└────────────────────────┬────────────────────────┘
                         │ OTLP (gRPC :4317)
┌────────────────────────▼────────────────────────┐
│              Observability VM                    │
│                                                  │
│  OTel Collector → Prometheus → Grafana           │
│                → Tempo     ↗                     │
│                → Loki     ↗                      │
│  Prometheus → Alertmanager → Telegram            │
└──────────────────────────────────────────────────┘
```

---

## 📚 Learning Roadmap

Dự án được chia thành 6 phases, mỗi phase tập trung vào một khía cạnh của observability:

| Phase | Chủ đề | Level | Trạng thái |
|-------|--------|-------|------------|
| **Phase 1** | Metrics — Prometheus, Node Exporter, cAdvisor | Cơ bản | ✅ |
| **Phase 2** | Logging — Loki, Promtail | Cơ bản | ✅ |
| **Phase 3** | Tracing — Tempo, OTel Collector, Tail-based Sampling | Trung cấp | ✅ |
| **Phase 4** | Alerting — Alertmanager, Recording Rules, Predictive Alerts | Trung cấp | ✅ |
| **Phase 5** | Application Instrumentation — Custom Metrics, Structured Logging | Nâng cao | ✅ |
| **Phase 6** | Correlation & SLO — Log→Trace, SLI/SLO, Error Budget | Nâng cao | ✅ |

Chi tiết: xem [task.md](task.md)

---

## 🚀 Quick Start

### Prerequisites

- Docker Engine ≥ 24.0
- Docker Compose ≥ 2.20
- 2 VMs (hoặc 1 VM đủ RAM) với network connectivity

### 1. Tạo external network

```bash
docker network create observability
```

### 2. Khởi động Observability VM

```bash
cd observability-vm/phase1-metrics   # hoặc phase nào bạn đang làm
docker compose up -d
```

### 3. Khởi động Applications VM

```bash
cd applications-vm
docker compose up -d
```

### 4. Truy cập

| Service | URL | Mô tả |
|---------|-----|-------|
| Web UI | `http://<app-vm>:8580` | E-commerce frontend |
| Grafana | `http://<obs-vm>:3000` | Dashboards (admin/admin) |
| Kafka UI | `http://<app-vm>:8585` | Kafka topics & consumers |
| Prometheus | `http://<obs-vm>:9090` | Metrics queries |

---

## 📂 Cấu Trúc Thư Mục

```
on-premises/
├── README.md                     ← File này
├── ARCHITECTURE.md               ← Sơ đồ Mermaid
├── ARCHITECTURE_DETAIL.md        ← Giải thích chi tiết
├── architecture_summary.md       ← Tổng kết kiến thức
├── task.md                       ← Learning roadmap checklist
├── devops-question.md            ← DevOps interview questions (Junior–Mid)
├── applications-vm/
│   ├── applications/             # Source code microservices
│   └── agents/                   # AI agent configs
└── observability-vm/
    ├── phase1-metrics/           # Prometheus + Node Exporter + cAdvisor
    ├── phase2-logging/           # Loki + Promtail
    ├── phase3-tracing/           # Tempo + OTel Collector
    ├── scripts/                  # Utility scripts
    └── storage/                  # Persistent data
```

---

## 📝 DevOps Interview Practice

Bộ câu hỏi phỏng vấn DevOps dựa trên lab này:

| File | Level | Số câu | Focus |
|------|-------|--------|-------|
| [devops-question.md](devops-question.md) | Junior–Mid + Stretch | 37 | Docker, Networking, Kafka, Observability, CI/CD, Troubleshooting |

> Câu hỏi dựa trên codebase thực tế, yêu cầu giải thích "why" chứ không chỉ "what".

---

## 🔗 Liên Quan

- [../README.md](../README.md) — Tổng quan toàn bộ dự án
- [../terraform/](../terraform/) — AWS infrastructure (Terraform)
- [../terraform/devops-question-m1-iac-core.md](../terraform/devops-question-m1-iac-core.md) — DevOps interview cho Terraform/AWS
