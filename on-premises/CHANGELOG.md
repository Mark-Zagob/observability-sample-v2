# 📋 Changelog

> Tài liệu theo dõi toàn bộ thay đổi của Reliability Lab theo thời gian.  
> Tuân thủ định dạng [Keep a Changelog](https://keepachangelog.com/), phiên bản tuân thủ [Semantic Versioning](https://semver.org/).

**Owner:** Platform Engineering Team — dungtt  
**Last Updated:** 2026-09-17

---

## [2.4.0] — 2026-09-17

### 🛡️ Week 1-2: Production-Grade Infrastructure Hardening

> **Milestone đầu tiên trên hành trình đưa Lab lên production-grade.**  
> Chi tiết implementation: [`WEEK1-2_CHANGES.md`](WEEK1-2_CHANGES.md) & [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md)

#### ✨ Added
- **3-Tier Network Segmentation** (`frontend` / `backend` / `data`) — giảm Blast Radius, áp dụng Zero Trust trong Lab
- **Network Connectivity Matrix** — ma trận rõ ràng service nào có thể reach service nào (xem [`WEEK1-2_CHANGES.md`](WEEK1-2_CHANGES.md))
- **Observability Stack Resource Allocation** — resource limits cho toàn bộ monitoring stack (Prometheus, Loki, Tempo, Grafana, OTel Collector, MinIO, agents)
- **Graceful Shutdown Contract** — document chính thức contract giữa Docker Compose (`stop_grace_period`) và application code (`graceful_timeout`)
- **Chaos Exercises Week 1-2** — 2 bài thực hành controlled: Noisy Neighbor (Memory Leak) + Network Isolation

#### 🔒 Security (Blast Radius Reduction)
- ✅ Network Segmentation: `web-ui` KHÔNG thể reach PostgreSQL (Zero Trust)
- ✅ `api-gateway` KHÔNG thể access data layer (Redis, Kafka, PostgreSQL)
- ✅ Compromise của bất kỳ frontend service nào đều không expose data layer
- ✅ Defense in Depth: Network + Resource + Container Hardening

#### 📊 Reliability (Noisy Neighbor Protection)
- ✅ CPU/Memory limits + reservations cho **12/12 services** trên App VM
- ✅ Resource limits cho **12/12 services** trên Observability VM
- ✅ Bulkhead Pattern — mỗi service có resource pool riêng, không kéo sập service khác
- ✅ OOM Killer targets service vi phạm limit, KHÔNG giết random containers (verified bằng `stress`)

#### 💾 Operability (Disk Pressure Management)
- ✅ Docker log rotation: `json-file` driver, `max-size: 10m`, `max-file: 5` (tối đa 50MB/container)
- ✅ Graceful Shutdown Contract: `stop_grace_period: 30s` (apps), `60s` (PostgreSQL/Kafka)
- ✅ Match với code-level `graceful_timeout: 25s` + 5s buffer cho OS/network teardown
- ✅ Kafka offset commit safety — không mất message khi container restart

#### 📝 Documentation
- ✅ Cập nhật `ARCHITECTURE.md` v2.3 → v2.4 (đồng bộ với hiện trạng codebase)
- ✅ Bổ sung "Graceful Shutdown Contract" section mới
- ✅ Bổ sung "Observability Stack Capacity Planning" table
- ✅ Đánh dấu hoàn thành các Planned Security Improvements: Network Segmentation, Resource Limits, Log Rotation
- ✅ Khởi tạo `CHANGELOG.md` (file này)
- ✅ Cập nhật `README.md` (root) — Architecture diagram thể hiện 3-tier networks, Lộ trình thực hành với Status column, So sánh On-Prem vs AWS table
- ✅ Cập nhật `EXPANSION_PLAN.md` v2.1 → v2.2 — Đánh dấu Phase 0 Infrastructure Level từ "CẦN TRIỂN KHAI" sang "ĐÃ HOÀN THÀNH"
- ✅ Cập nhật `BREAK_TEST_RECOVERY.md` — Thêm Week 1-2 Note về `stop_grace_period` timing (30s/60s)
- ✅ Cập nhật `INCIDENT_SIMULATION_GUIDE.md` — Thêm Week 1-2 Note cho Experiment 7 (Memory Pressure) về baseline memory limits

#### 🎓 SRE Concepts Learned
| Concept | Application |
|---------|-------------|
| `Network Segmentation` | 3-tier Docker bridge networks |
| `Blast Radius Reduction` | web-ui compromise → data layer safe |
| `Noisy Neighbor Problem` | Resource limits prevent cascade OOM |
| `Bulkhead Pattern` | Isolated resource pools per service |
| `Disk Pressure Management` | Log rotation = #1 production killer prevention |
| `Graceful Shutdown Contract` | Orchestrator ↔ app timeout alignment |
| `Zero Trust Architecture` | Never trust, always verify (network-level) |
| `Defense in Depth` | Network + Resource + Security hardening |

---

## [2.3.0] — 2026-07-10

### 🔬 Phase 5: Production Guardrails & Observability Deep-Dive

#### ✨ Added (Design Patterns)
- **Pattern #16:** Database Driver Resilience — TCP Keep-Alive + `statement_timeout` cho PostgreSQL
- **Pattern #17:** Frontend SRE — Page Visibility API chống phantom traffic
- **Pattern #18:** OTel Histogram Custom Buckets — P95/P99 chính xác cho workloads seconds-scale
- **Pattern #19:** Kafka Producer Natural Batching — `linger.ms: 50ms` + `batch.size: 16KB`
- **Pattern #20:** Traffic Source Tagging — phân biệt `synthetic_probe` / `synthetic_loadtest` / `browser`
- **Pattern #21:** Graceful Degradation — Redis down vẫn cho phép payment processing

#### 📊 Observability
- Traffic Guards trên SLO burn rate alerts (tránh phantom alerts khi traffic = 0)
- Custom OTel histogram buckets cho 8 `*_duration_seconds` metrics
- `traffic_source` label trên tất cả Prometheus metrics

#### 📝 Documentation
- Thêm ADR-011 (Custom OTel Buckets), ADR-012 (TCP Keep-Alive), ADR-013 (Page Visibility API)

---

## [2.2.0] — 2026-07-10

### ⚡ Phase 5: Core Resilience Patterns

#### ✨ Added (Design Patterns)
- **Pattern #11:** Graceful Shutdown Manager — callback registry pattern (`shared/shutdown_handler.py`)
- **Pattern #12:** Circuit Breaker — `pybreaker` wrap Payment Gateway
- **Pattern #13:** Auto-Migration — schema-on-startup, idempotent, cross-env (Docker Compose + AWS ECS)
- **Pattern #14:** HTTP Semantic Mapping — business status → HTTP status (`shared/errors.py`)
- **Pattern #15:** OTel Sidecar Watchdog — auto-restart task khi ADOT sidecar chết (AWS-only)

#### 🚩 Feature Flags
- `ENABLE_REDIS` — disable Redis trên AWS Phase 1 (graceful degradation)
- `ENABLE_KAFKA` — disable Kafka trên AWS Phase 1

---

## [2.1.0] — 2026-05-28

### 📐 Documentation Quality Pass

- Enhanced Mermaid diagrams (topology, sequence, ER)
- Added Document Metadata table (status, version, owner, reviewers)
- Cross-references giữa các tài liệu (ARCHITECTURE ↔ INCIDENT_RUNBOOK ↔ BREAK_TEST_RECOVERY)

---

## [2.0.0] — 2026-05-20

### 🏗️ Architecture Documentation Overhaul

#### ✨ Added
- Network Architecture section (VM specs, Port Exposure, Firewall Rules, DNS Resolution)
- Security Architecture section (Current State + Planned Improvements)
- Capacity Planning section (Resource Allocation, Connection Pool Sizing, Kafka Partitions)
- Failure Modes & Recovery section (SPOFs, Expected Behavior, Data Durability, Cascades)
- DevOps Knowledge Applied section

---

## [1.0.0] — 2026-01-15

### 🎉 Initial Release

- E-commerce microservices platform (6 services: API Gateway, Order, Payment, Traffic Gen, Notification Worker, Inventory Worker)
- Full observability stack trên Observability VM (Prometheus, Grafana, Loki, Tempo, OTel Collector)
- Kafka KRaft mode (ADR-001 — không dùng ZooKeeper)
- MinIO làm S3 backend cho Loki/Tempo (ADR-002)
- 10 Design Patterns (Patterns #1–#10)
- 5 ADRs đầu tiên (ADR-001 → ADR-005)

---

## 📊 Versioning Scheme

| Type | Format | Khi nào bump |
|------|--------|--------------|
| **Major** | x.0.0 → y.0.0 | Thay đổi kiến trúc lớn: thêm service mới, thay đổi communication pattern, thay đổi data layer |
| **Minor** | x.y.0 → x.(y+1).0 | Thêm pattern mới, feature mới, section mới vào documentation |
| **Patch** | x.y.z → x.y.(z+1) | Bug fixes, clarifications, typo fixes trong documentation |

---

## 🔗 Related Documents

| Document | Purpose |
|----------|---------|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Kiến trúc hiện tại (As-Is Blueprint) |
| [`EXPANSION_PLAN.md`](EXPANSION_PLAN.md) | Kế hoạch mở rộng (To-Be Roadmap) |
| [`ROADMAP_PRODUCTION_GRADE.md`](ROADMAP_PRODUCTION_GRADE.md) | Execution plan 1 năm đưa Lab lên production-grade |
| [`WEEK1-2_CHANGES.md`](WEEK1-2_CHANGES.md) | Chi tiết implementation Week 1-2 hardening |
| [`DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) | Hướng dẫn deploy lên Linux VMs |
| [`INCIDENT_RUNBOOK.md`](INCIDENT_RUNBOOK.md) | 24 alert runbooks |
| [`INCIDENT_SIMULATION_GUIDE.md`](INCIDENT_SIMULATION_GUIDE.md) | 12 incident experiments |
| [`BREAK_TEST_RECOVERY.md`](BREAK_TEST_RECOVERY.md) | 28 break/test/recovery drills |

---

> 🛡️ *"Every change to production should be observable, reversible, and documented. If it's not in the changelog, it didn't happen."* — SRE Principle
