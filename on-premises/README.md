# 🖥️ On-Premises — Production-Grade Observability & Reliability Lab

> **Không phải toy project.** Đây là sandbox được thiết kế để rèn luyện tư duy System Design, SRE và Reliability Engineering ở tiêu chuẩn production.
> Hệ thống E-commerce Microservices (Python/Flask) với full-stack observability (Metrics, Logs, Traces) và Incident Management, chạy cô lập trên 2 VMs bằng Docker Compose.

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker) ![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python) ![Observability](https://img.shields.io/badge/Observability-OTel%20%7C%20Prometheus%20%7C%20Loki%20%7C%20Tempo-orange) ![SRE](https://img.shields.io/badge/SRE-SLO%20%7C%20Error%20Budget%20%7C%20Chaos-red)

## 🎯 Mục tiêu & Đối tượng
- **Dành cho:** DevOps / SRE / Platform Engineer / Backend Developer muốn vượt khỏi mức "deploy & monitor cơ bản".
- **Kết quả đạt được:**
  - Đọc & thiết kế dashboard theo chuẩn RED/USE + Multi-Window Multi-Burn-Rate.
  - Xử lý incident theo quy trình: Triage → SEV Assessment → Mitigation → Blameless Post-Mortem.
  - Hiểu sâu internals của PostgreSQL, Kafka, Redis, OTel Collector qua Break/Test/Recovery.
  - Áp dụng Python production patterns: Gunicorn tuning, OTel auto-instrumentation, connection pooling, RFC 7807, idempotency.

---
## ⚡ Quick Start & Prerequisites
| Yêu cầu | Chi tiết |
|---------|----------|
| **Hardware** | Tối thiểu 8GB RAM, 4 vCPU (khuyến nghị 16GB/8 vCPU để chạy song song 2 VMs + Chaos) |
| **Software** | Docker ≥ 24.0, Docker Compose ≥ 2.20, `curl`, `jq`, `make` (optional) |
| **Network** | 2 VMs hoặc 2 Docker contexts: `applications-vm` (app stack) & `observability-vm` (monitoring stack) |

```bash
# 1. Clone & di chuyển vào thư mục gốc
git clone <your-repo-url> && cd observability-lab

# 2. Khởi tạo hạ tầng lưu trữ & observability
cd observability-vm/storage && docker compose up -d
cd ../phase1-metrics && docker compose up -d

# 3. Deploy ứng dụng E-commerce
cd ../../applications-vm && docker compose up -d

# 4. Verify hệ thống
curl -s http://localhost:5000/health | jq .
# Mở Grafana: http://<observability-vm-ip>:3000 (admin/admin)
```

>⚠️ Safety First: Lab sử dụng Chaos Experiments có chủ đích. Luôn chạy trên môi trường cô lập. Dùng docker compose down -v để cleanup toàn bộ state khi cần reset.
---

## 🧠 Core Engineering & SRE Concepts
Dự án không chỉ là "deploy code lên Docker", mà là nơi thực hành các patterns và trade-offs thực tế mà Senior/Staff Engineer phải đối mặt:

| Khía cạnh | Patterns & Concepts | Production Trade-off / Why it matters |
|-----------|---------------------|----------------------------------------|
| **System Design** | Event-Driven (Kafka KRaft), Cache-Aside (Redis), Pessimistic Locking (`SELECT FOR UPDATE`), BFF, Idempotency Keys | Consistency vs Latency. Idempotency chống duplicate charge. Pessimistic lock tránh race condition khi stock thấp. |
| **Python Engineering** | Gunicorn (`sync` vs `gevent`), `psycopg2` pool, OTel auto-instrumentation, RFC 7807 Problem Details, structured logging | Worker class ảnh hưởng throughput. Connection pool tránh DB exhaustion. RFC 7807 chuẩn hóa error contract cho client. |
| **Reliability (SRE)** | SLI/SLO & Error Budgets, MWMBR Alerting (14.4x / 3x), Traffic Guards, Active Probing (Blackbox) | Chống phantom alerts khi traffic = 0. Burn rate giúp phát hiện SLO breach sớm hơn threshold tĩnh. |
| **Observability** | 3 Pillars + Correlation (TraceID injected vào Logs/Metrics), Spanmetrics Connector, OTel Collector pipelines | Không correlation = blind debugging. Spanmetrics auto-generate RED metrics mà không cần instrument code. |
| **Incident Mgmt** | SEV Matrix, Runbook-driven response, Blameless Post-Mortem, 5 Whys, Error Budget Policy | Giảm MTTR nhờ runbook chuẩn hóa. Post-mortem tập trung vào systemic gap, không đổ lỗi cá nhân. |

---
## 📊 Observability Stack & Correlation Strategy
Hệ thống áp dụng mô hình **3 Pillars + Correlation** chuẩn OpenTelemetry:

| Component | Vai trò | Dữ liệu thu thập | Correlation Key |
|-----------|---------|------------------|-----------------|
| **OTel Collector** | Agent & Pipeline | Receives OTLP → Process → Export | `trace_id`, `span_id` |
| **Prometheus** | Metrics Storage & Alerting | RED metrics, Business KPIs, Infra USE | `trace_id` (via exemplars) |
| **Loki** | Log Aggregation | Structured JSON logs từ Flask/Gunicorn | `trace_id` (injected via OTel logging instrumentation) |
| **Tempo** | Distributed Tracing | Full request lifecycle across services | `trace_id` (primary key) |
| **Grafana** | Visualization & Incident UI | Dashboards, Explore, Alerting UI | Cross-datasource linking via `trace_id` |

> 🔗 **Workflow thực tế:** Alert firing → Grafana Explore → Filter by `trace_id` → Jump to Tempo Trace → View Loki Logs cùng trace → Root cause trong < 3 phút.
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

## 🗺️ Lộ trình thực hành & Điều hướng tài liệu
Repository được thiết kế theo lộ trình tăng dần về độ phức tạp và tư duy vận hành:

| Giai đoạn | Tài liệu chính | Kỹ năng trọng tâm | Độ khó |
|-----------|----------------|-------------------|--------|
| **Phase 1-3** | `observability-vm/phase{1,2,3}/README.md` | Deploy stack, cấu hình OTel pipeline, dashboard cơ bản | ⭐ |
| **Phase 4-5** | `applications-vm/` + `ARCHITECTURE.md` | Microservices communication, DB/Kafka internals, caching strategy | ⭐⭐ |
| **Incident Drill** | `INCIDENT_SIMULATION_GUIDE.md` + `INCIDENT_RUNBOOK.md` | Đọc dashboard theo Incident Flow, Triage, SEV assessment, Escalation | ⭐⭐⭐ |
| **Deep Internals** | `BREAK_TEST_RECOVERY.md` | Phá & khôi phục PostgreSQL, Kafka, Redis, Prometheus qua CLI/Query | ⭐⭐⭐ |
| **Post-Mortem** | `post-mortems/00-TEMPLATE.md` + `01-GOLDEN-EXAMPLE-*.md` | Viết Blameless RCA, 5 Whys, Action Items trackable | ⭐⭐ |
| **Scale & Evolution** | `EXPANSION_PLAN.md` | Saga, CQRS, Circuit Breaker, TLS, Network Segmentation, SLO redesign | ⭐⭐⭐⭐ |
| **Interview Prep** | `devops-question.md` & `devops-question-senior.md` | Trade-offs, System Design, SRE mindset, Production debugging | ⭐⭐⭐ |

> 💡 **Reliability PM Note:** Đừng đợi code hoàn thiện mới nghĩ đến monitoring. Hãy đọc `EXPANSION_PLAN.md` để định nghĩa SLI/SLO và thiết kế Runbook cho các failure domain mới (Saga compensation, CQRS sync lag, circuit breaker open).

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

---
## 🤝 Đóng góp & Feedback
Repository này là môi trường học tập mở. Nếu bạn phát hiện gap trong runbook, đề xuất experiment mới, hoặc muốn chia sẻ post-mortem từ lab của bạn, hãy mở Issue hoặc PR.

## 📜 License
MIT License — Tự do sử dụng cho mục đích học tập, đào tạo nội bộ và phỏng vấn. Không bảo hành cho môi trường production thực tế.

---
> 🛡️ *"Reliability is the most important feature. If users can't access the system, nothing else matters."* — Google SRE Book