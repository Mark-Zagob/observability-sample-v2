# 📋 Changelog

> Tài liệu theo dõi toàn bộ thay đổi của Reliability Lab theo thời gian.  
> Tuân thủ định dạng [Keep a Changelog](https://keepachangelog.com/), phiên bản tuân thủ [Semantic Versioning](https://semver.org/).

**Owner:** Platform Engineering Team — dungtt  
**Last Updated:** 2026-09-17

---

## [2.4.3] — 2026-09-17

### 🐛 Phase 4.5: Fix Pyroscope Storage Permission Denied

#### ❌ Root Cause
The Pyroscope container crashed with `permission denied` when trying to write profiling data:

```
mkdir /var/lib/pyroscope/anonymous/local: mkdir /var/lib/pyroscope/anonymous: permission denied
```

**Root Cause:** The `grafana/pyroscope:1.13.0` Docker image runs as non-root user `pyroscope` (UID 10001, GID 10001). The image's Dockerfile:

1. **Pre-creates `/data` with correct ownership** (10001:10001) via `COPY --chown=pyroscope:pyroscope`
2. **Declares `VOLUME /data`** — Docker copy-up semantics preserve the 10001:10001 ownership
3. **Does NOT pre-create `/var/lib/pyroscope`** — this path doesn't exist in the image

When we mounted the named volume `pyroscope_data` to `/var/lib/pyroscope`, Docker created the volume with **root:root ownership** (default). Pyroscope (running as UID 10001) could not write to the root-owned directory.

**Positive Signal:** The logs showed `User-Agent: pyroscope-rs/pyspy/1.2.3` — confirming that the SDK integration from Phase 4.5 (gunicorn fork-safety, memory profiling) was working correctly. The apps were sending data to Pyroscope, but Pyroscope couldn't persist it.

#### ✅ Fix Applied (Minimal Viable Change)

**Changed storage path from `/var/lib/pyroscope` to `/data`:**

1. **`pyroscope/config.yaml`:**
   ```yaml
   pyroscopedb:
     data_path: /data  # ← Changed from /var/lib/pyroscope
     min_free_disk_gb: 1  # ← Lowered from 5GB for lab safety
   ```

2. **`docker-compose.yml`:**
   ```yaml
   volumes:
     - pyroscope_data:/data  # ← Changed from /var/lib/pyroscope
   ```

**Why this works:**
- Named volumes mounted at `/data` inherit the image's pre-configured 10001:10001 ownership
- Pyroscope (UID 10001) can write to the volume
- No init container or `user: root` workaround needed

#### 🔄 Rollback Plan

If this fix causes issues, revert to the original configuration and use an init container:

```yaml
services:
  pyroscope-init:
    image: alpine:3.20
    user: root
    volumes:
      - pyroscope_data:/var/lib/pyroscope
    command: ["sh", "-c", "chown -R 10001:10001 /var/lib/pyroscope"]
    restart: "no"

  pyroscope:
    user: "10001:10001"
    depends_on:
      pyroscope-init:
        condition: service_completed_successfully
```

#### 🎓 SRE Concepts Applied

| Concept | Application |
|---------|-------------|
| **Docker Named Volume Copy-Up** | Volumes inherit content + ownership from the image's mountpoint at creation time |
| **Least Privilege Principle** | Run containers as non-root (UID 10001), not `user: root` |
| **Blast Radius = 0** | Fix only affects Pyroscope storage path, no impact on app tier or DB |
| **Silent Failure Detection** | Logs showed `permission denied` + `User-Agent: pyroscope-rs` — SDK working, storage broken |

#### 📝 Files Changed

| File | Change |
|------|--------|
| `observability-vm/phase4-profiling/pyroscope/config.yaml` | `data_path: /var/lib/pyroscope` → `/data`, `min_free_disk_gb: 5` → `1` |
| `observability-vm/phase4-profiling/docker-compose.yml` | Volume mount: `/var/lib/pyroscope` → `/data` |

---

## [2.4.2] — 2026-09-17

### 🐛 Phase 4.5: Fix Pyroscope SDK Integration Bugs

#### ❌ Root Cause
The `profiling_setup.py` shared module contained **incorrect API parameter names** that caused `pyroscope.configure()` to fail silently with a `TypeError`. The service continued running but **no profiling data was collected** — a classic Silent Failure anti-pattern.

**Specific bugs:**
1. `app_name=service_name` — **WRONG parameter name**. The official Pyroscope Python SDK requires `application_name`, not `app_name` [[1]].
2. `detect_subthread_spans=True` — **INVALID parameter**. This parameter doesn't exist in the `pyroscope-io` SDK API [[1]].
3. Memory profiling was **disabled by default** (`mem_enabled` defaults to `False`), preventing memory leak detection — one of the primary use cases for continuous profiling.
4. Gunicorn fork-safety was not addressed: Pyroscope SDK starts background threads on `configure()`, which are **NOT inherited after fork** [[1]].

#### ✅ Fix Applied

**1. Fixed `profiling_setup.py` (shared module):**
- Changed `app_name` → `application_name` (correct official API) [[1]]
- Removed invalid `detect_subthread_spans` parameter
- Added `mem_enabled=True` for memory allocation profiling
- Added `gil_only=True` for GIL contention detection
- Added `cpu_enabled=True` explicitly
- Added `ENABLE_MEMORY_PROFILING` env var for feature flag control
- Added `init_profiling_for_gunicorn()` helper for fork-safe initialization

**2. Created gunicorn.conf.py for all services:**
- `api-gateway/gunicorn.conf.py` — NEW (was hardcoded in Dockerfile)
- `notification-worker/gunicorn.conf.py` — NEW (was hardcoded in Dockerfile)
- `inventory-worker/gunicorn.conf.py` — NEW (was hardcoded in Dockerfile)
- Updated `order-service/gunicorn.conf.py` — added `post_worker_init` profiling
- Updated `payment-service/gunicorn.conf.py` — added `post_worker_init` profiling

**3. Updated all app.py files:**
- Added `if 'gunicorn' not in sys.modules:` guard to module-level profiling init
- Production path: profiling initialized in `post_worker_init` (fork-safe) [[1]]
- Development path: profiling initialized at module import (python app.py)

**4. Updated all Dockerfiles:**
- Changed hardcoded gunicorn CLI args → `-c gunicorn.conf.py` for consistency
- Added `COPY gunicorn.conf.py .` to each Dockerfile

**5. Provisioned Grafana datasource:**
- Copied `pyroscope.yml` to `phase1-metrics/grafana/provisioning/datasources/`
- Grafana will auto-load Pyroscope datasource on next restart

#### 📝 Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `applications/shared/profiling_setup.py` | MODIFIED | Fix API params, enable memory profiling |
| `applications/api-gateway/gunicorn.conf.py` | **NEW** | Gunicorn config with profiling hook |
| `applications/notification-worker/gunicorn.conf.py` | **NEW** | Gunicorn config with profiling hook |
| `applications/inventory-worker/gunicorn.conf.py` | **NEW** | Gunicorn config with profiling hook |
| `applications/order-service/gunicorn.conf.py` | MODIFIED | Add `post_worker_init` profiling |
| `applications/payment-service/gunicorn.conf.py` | MODIFIED | Add `post_worker_init` profiling |
| `applications/*/app.py` (6 files) | MODIFIED | Add gunicorn guard for dev/prod split |
| `applications/*/Dockerfile` (4 files) | MODIFIED | Use `-c gunicorn.conf.py` |
| `observability-vm/phase1-metrics/grafana/provisioning/datasources/pyroscope.yml` | **NEW** | Grafana datasource auto-provisioning |

#### 🔄 Rollback Plan
```bash
cd applications-vm/applications
# Revert profiling_setup.py
git checkout HEAD -- shared/profiling_setup.py
# Remove new gunicorn configs (they didn't exist before)
rm api-gateway/gunicorn.conf.py
rm notification-worker/gunicorn.conf.py
rm inventory-worker/gunicorn.conf.py
# Revert modified files
git checkout HEAD -- order-service/gunicorn.conf.py payment-service/gunicorn.conf.py
git checkout HEAD -- */app.py */Dockerfile
```

#### 🎓 SRE Concepts Applied
| Concept | Application |
|---------|-------------|
| `Silent Failure Detection` | SDK misconfiguration caused no data — not a crash. Only discovered by code review. |
| `Fork Safety` | Pyroscope starts background threads — must initialize AFTER gunicorn fork [[1]] |
| `Production-Grade Defaults` | Enable memory profiling (detect leaks) and GIL contention detection |
| `Configuration as Code` | gunicorn.conf.py > CLI args (version-controlled, testable, consistent) |
| `Feature Flag Pattern` | `ENABLE_MEMORY_PROFILING` env var for gradual rollout |
| `Development/Production Parity` | Same code path for `python app.py` and `gunicorn app:app` |

---

## [2.4.1] — 2026-09-17

### 🐛 Phase 4.5: Fix Pyroscope Container Startup Failure

#### ❌ Root Cause
Pyroscope v1.13.0 container failed to start with:
```
flag provided but not defined: -retention-period
```
The `docker-compose.yml` used **deprecated CLI flags** from the pre-1.0 era (`pyroscope/pyroscope`), which were **removed** in the `grafana/pyroscope` 1.0+ rewrite [[15]].

Specifically:
- `-retention-period` — **removed in v1.0**, replaced by `limits.compactor_blocks_retention_period` in YAML config
- `-ingestion.max-ingestion-rate` — **non-existent flag**, ingestion rate is controlled via `limits.ingestion_rate_mb`
- `-config.file=/etc/pyroscope/server.yml` — referenced the **old config path** (`server.yml`), new path is `config.yaml` [[15]]
- No config file was actually mounted into the container

#### ✅ Fix Applied
1. **Created** `pyroscope/config.yaml` — proper v1.13 configuration file with:
   - `compactor_blocks_retention_period: 168h` (7-day retention)
   - `ingestion_rate_mb: 10` / `ingestion_burst_size_mb: 20` (rate limiting)
   - `max_global_series_per_tenant: 100000` (cardinality guard)
   - `compactor.compaction_interval: 15m` + `deletion_delay: 12h`
   - `pyroscopedb` disk retention settings (`enforcement_interval: 5m`)

2. **Fixed** `docker-compose.yml`:
   - Removed all invalid CLI flags
   - Changed to: `-config.file=/etc/pyroscope/config.yaml`
   - Added volume mount: `./pyroscope/config.yaml:/etc/pyroscope/config.yaml:ro`

#### 📝 Files Changed
- `observability-vm/phase4-profiling/docker-compose.yml` — command + volumes
- `observability-vm/phase4-profiling/pyroscope/config.yaml` — **new file**

#### 🔄 Rollback Plan
If issues arise, revert to the old compose (but it will fail to start):
```bash
cd observability-vm/phase4-profiling
# The old config had invalid flags — there is no safe rollback state
# Simply keep the fixed version
```

#### 🎓 SRE Lesson
| Concept | Application |
|---------|-------------|
| `Breaking Changes in Major Versions` | Pyroscope 1.0 removed many CLI flags — always check upgrade guides |
| `Configuration as Code` | YAML config file > CLI flags (version-controlled, auditable, testable) |
| `Look Before You Leap` | Read the official upgrade guide before bumping image versions |
| `Minimal Viable Change` | Fixed by moving config to file instead of guessing new flag names |

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
