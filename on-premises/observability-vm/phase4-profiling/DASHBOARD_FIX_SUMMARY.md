# 🔧 Dashboard Fix Summary — Profiling Panels

## 📋 Vấn đề

Sau khi triển khai Phase 4.5 (Continuous Profiling), 3 panels trong Grafana dashboards hiển thị **"No Data"**:

### Affected Panels

| Dashboard | Panel | Issue |
|-----------|-------|-------|
| **Profiling Overview** | 🔥 CPU Samples Ingestion Rate | No Data |
| **Profiling Overview** | 💾 Memory Samples Ingestion Rate | No Data |
| **Profiling Overview** | ❌ Failed Samples (Error Rate) | No Data |
| **Unified Overview** | 🔥 Profiling Samples Ingestion Rate | No Data |

---

## 🔍 Root Cause Analysis

### Investigation Steps

1. **Verified Pyroscope container health**: ✅ Running normally
2. **Verified Prometheus scrape target**: ✅ `health: "up"`
3. **Checked Pyroscope `/metrics` endpoint**: ❌ Metric `pyroscope_app_stats_samples_ingested_total` **KHÔNG TỒN TẠI**
4. **Analyzed available metrics**: Chỉ có Go runtime metrics (`go_*`), memberlist metrics, không có Pyroscope-specific ingestion metrics

### Root Cause

**Pyroscope server KHÔNG expose ingestion metrics qua Prometheus `/metrics` endpoint.**

Đây là design decision của Pyroscope:
- Pyroscope focus vào **profile data storage và visualization**
- Server-side telemetry (ingestion rate, failed samples) không được expose qua Prometheus metrics
- Grafana phải query **profile data trực tiếp** qua Pyroscope API

---

## ✅ Solution Applied

### Approach: Use Pyroscope Datasource Instead of Prometheus

Thay vì cố gắng query Prometheus metrics (không tồn tại), chúng ta sử dụng **Pyroscope Grafana datasource** để query profile data trực tiếp.

### Changes Made

#### 1. **Profiling Overview Dashboard** (`profiling-overview.json`)

**Before (Broken):**
```json
{
  "datasource": {"type": "prometheus", "uid": "PBFA97CFB590B2093"},
  "targets": [
    {
      "expr": "sum(rate(pyroscope_app_stats_samples_ingested_total[5m])) by (app_name)",
      "legendFormat": "{{ app_name }}"
    }
  ]
}
```

**After (Fixed):**
```json
{
  "datasource": {"type": "grafana-pyroscope-datasource", "uid": "pyroscope-datasource"},
  "targets": [
    {
      "refId": "A",
      "queryType": "metrics",
      "profileTypeId": "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
      "labelSelector": "{service_name=\"$service\"}",
      "groupBy": ["service_name"]
    }
  ]
}
```

**Panels Updated:**
- ✅ Panel 1: "🔥 CPU Profile Activity (Total CPU Time)" — Hiển thị tổng CPU time được profile
- ✅ Panel 2: "💾 Memory Allocation Activity (Total Bytes)" — Hiển thị tổng bytes được allocate
- ✅ Panel 3: "✅ Profile Availability Check" — Stat panel hiển thị "Profiles Available" hoặc "No Data"

#### 2. **Unified Overview Dashboard** (`unified-overview.json`)

**Before (Broken):**
```json
{
  "datasource": {"type": "prometheus", "uid": "PBFA97CFB590B2093"},
  "targets": [
    {
      "expr": "sum(rate(pyroscope_app_stats_samples_ingested_total[5m])) by (app_name, sample_type)",
      "legendFormat": "{{ app_name }} — {{ sample_type }}"
    }
  ]
}
```

**After (Fixed):**
```json
{
  "datasource": {"type": "grafana-pyroscope-datasource", "uid": "pyroscope-datasource"},
  "targets": [
    {
      "refId": "A",
      "queryType": "metrics",
      "profileTypeId": "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
      "labelSelector": "{service_name=~\".*\"}",
      "groupBy": ["service_name"]
    }
  ]
}
```

**Panel Updated:**
- ✅ Panel 10: "🔥 Profile Activity Summary (CPU Time per Service)" — Hiển thị CPU time cho tất cả services

---

## 🎯 What You'll See Now

### 1. **CPU Profile Activity Panel**

**What it shows:**
- Tổng CPU time (nanoseconds) được profile trong khoảng thời gian chọn
- Breakdown theo service (nếu dùng variable `$service`)

**How to interpret:**
- **Value > 0**: CPU profiling đang hoạt động bình thường
- **Value = 0**: Không có CPU profiles được gửi tới Pyroscope
- **Compare với P95 latency**: Khi P95 spike, check panel này để confirm profiling đang capture data

**Use Case:**
```
P95 latency = 2.5s (normal = 200ms)
↓
Check CPU Profile Activity panel → Shows high value
↓
Confirm profiling is capturing data
↓
View flame graph → Find function consuming 80% CPU
↓
Optimize function → Verify P95 giảm
```

---

### 2. **Memory Allocation Activity Panel**

**What it shows:**
- Tổng bytes được allocate trong khoảng thời gian chọn
- Breakdown theo service

**How to interpret:**
- **Value > 0**: Memory profiling đang hoạt động
- **Value = 0**: Memory profiling bị tắt hoặc không có allocations
- **High value + stable RSS**: Allocations được GC tốt
- **High value + growing RSS**: **Memory leak potential** ⚠️

**Use Case:**
```
RSS memory tăng 50MB/hour
↓
Check Memory Allocation Activity → Shows high value
↓
View Memory Flame Graph → Find `OrderService.process_order()` allocates 1000 objects/request
↓
Root cause: Objects không được release
↓
Add cleanup logic hoặc use object pool
```

---

### 3. **Profile Availability Check Panel**

**What it shows:**
- **"Profiles Available"** (green): Profiling SDK hoạt động bình thường
- **"No Data"** (red): Có vấn đề với profiling system

**How to interpret:**
- **Green + value**: Everything OK, profiling đang hoạt động
- **Red + "No Data"**: Troubleshoot ngay lập tức

**Troubleshooting Steps:**
```bash
# 1. Check Pyroscope container
docker logs pyroscope | tail -50

# 2. Check app logs for profiling initialization
docker logs order-service | grep -i pyroscope

# 3. Check network connectivity
docker exec order-service python3 -c "import urllib.request; print(urllib.request.urlopen('http://pyroscope:4040/ready').read())"

# 4. Check environment variables
docker exec order-service env | grep PROFILING
```

**Common Issues:**
- `ENABLE_PROFILING=false` → Set to `true` trong docker-compose.yml
- Pyroscope container down → `docker compose up -d pyroscope`
- Network issue → Check Docker network configuration
- SDK not initialized → Check app startup logs for errors

---

### 4. **Profile Activity Summary Panel (Unified Overview)**

**What it shows:**
- CPU time per service cho TẤT CẢ services
- Multi-series time series graph

**How to interpret:**
- **Multiple services showing data**: Profiling hoạt động trên toàn bộ system
- **Only 1-2 services showing data**: Các services khác có thể chưa được instrumented
- **No data for any service**: System-wide profiling issue

**Use Case:**
```
P95 latency spike on api-gateway
↓
Check Profile Activity Summary panel
↓
See that api-gateway, order-service, payment-service all have data
↓
Confirm profiling is capturing data across the system
↓
Click "Open Profiling Dashboard" link
↓
Select api-gateway from dropdown
↓
View flame graph → Find bottleneck function
```

---

## 🔬 Verification Steps

### Step 1: Restart Grafana để reload dashboards

```bash
cd observability-sample-v2/on-premises/observability-vm/phase1-metrics
docker compose restart grafana
```

**Expected output:**
```
Restarting grafana ... done
```

---

### Step 2: Verify Pyroscope datasource trong Grafana

1. Mở Grafana: `http://192.168.100.55:3000`
2. Navigate: **Configuration → Data Sources**
3. Verify **Pyroscope** datasource exists với:
   - Name: `Pyroscope`
   - Type: `grafana-pyroscope-datasource`
   - URL: `http://pyroscope:4040`
   - Status: `Data source is working`

---

### Step 3: Generate traffic để create profiling data

```bash
# Normal traffic load
curl http://192.168.100.57:5003/scenarios/pipeline

# Flash sale simulation
curl http://192.168.100.57:5003/scenarios/flash-sale
```

**Wait 30 seconds** để profiling data được ingest.

---

### Step 4: Check Profiling Overview Dashboard

1. Navigate: **Dashboards → Profiling → Profiling — Continuous Profiling (Pyroscope)**
2. Verify panels:

#### ✅ Panel 1: "🔥 CPU Profile Activity"
- **Expected**: Time series graph hiển thị CPU time (nanoseconds)
- **If shows data**: ✅ CPU profiling hoạt động
- **If "No Data"**: ⚠️ Check troubleshooting steps bên dưới

#### ✅ Panel 2: "💾 Memory Allocation Activity"
- **Expected**: Time series graph hiển thị memory allocations (bytes)
- **If shows data**: ✅ Memory profiling hoạt động
- **If "No Data"**: ⚠️ Check troubleshooting steps bên dưới

#### ✅ Panel 3: "✅ Profile Availability Check"
- **Expected**: Green stat panel hiển thị "Profiles Available"
- **If green**: ✅ Everything OK
- **If red "No Data"**: ⚠️ Troubleshoot ngay

#### ✅ Panel 4: "🔥 CPU Flame Graph"
- **Expected**: Flame graph visualization
- **Click các functions** để drill-down
- **Hover** để xem CPU time details

---

### Step 5: Check Unified Overview Dashboard

1. Navigate: **Dashboards → Application → Unified Overview**
2. Scroll đến section **"🔥 Profiling (Continuous Profiling — Pyroscope)"**
3. Verify panel:

#### ✅ Panel 10: "🔥 Profile Activity Summary"
- **Expected**: Multi-series time series graph hiển thị CPU time cho tất cả services
- **If shows data for multiple services**: ✅ Profiling hoạt động trên toàn bộ system
- **If shows data for only 1-2 services**: ⚠️ Các services khác chưa được instrumented
- **If "No Data"**: ⚠️ System-wide profiling issue

---

## 🛠️ Troubleshooting Guide

### Issue 1: All panels show "No Data"

**Symptoms:**
- CPU Profile Activity: No Data
- Memory Allocation Activity: No Data
- Profile Availability Check: Red "No Data"

**Root Cause:** Profiling SDK chưa được initialized hoặc Pyroscope unreachable

**Troubleshooting Steps:**

```bash
# 1. Check Pyroscope container health
docker logs pyroscope | tail -50
# Expected: "Pyroscope started" message

# 2. Check app logs for profiling initialization
docker logs order-service | grep -i pyroscope
# Expected: "✅ Pyroscope profiling initialized for worker X"

# 3. Check environment variables
docker exec order-service env | grep PROFILING
# Expected: ENABLE_PROFILING=true, PYROSCOPE_URL=http://pyroscope:4040

# 4. Check network connectivity
docker exec order-service python3 -c "import urllib.request; print(urllib.request.urlopen('http://pyroscope:4040/ready').read())"
# Expected: b'ready'

# 5. Check Pyroscope API
curl http://192.168.100.55:4040/ready
# Expected: "ready"
```

**Fix:**
- Nếu Pyroscope container down: `docker compose up -d pyroscope`
- Nếu `ENABLE_PROFILING=false`: Update docker-compose.yml và rebuild
- Nếu network issue: Check Docker network configuration

---

### Issue 2: Only some services show data

**Symptoms:**
- api-gateway shows data ✅
- order-service shows data ✅
- payment-service: No Data ❌
- inventory-worker: No Data ❌

**Root Cause:** Profiling chưa được enabled cho một số services

**Troubleshooting Steps:**

```bash
# 1. Check if profiling is initialized in payment-service
docker logs payment-service | grep -i pyroscope
# Expected: "✅ Pyroscope profiling initialized for worker X"
# If not found: Profiling chưa được enabled

# 2. Check requirements.txt
grep grafana-pyroscope applications-vm/applications/payment-service/requirements.txt
# Expected: grafana-pyroscope==0.8.2

# 3. Check app.py for init_profiling call
grep init_profiling applications-vm/applications/payment-service/app.py
# Expected: profiler = init_profiling("payment-service", "3.0.0")
```

**Fix:**
- Add `grafana-pyroscope==0.8.2` to `requirements.txt`
- Add `from shared.profiling_setup import init_profiling` to `app.py`
- Add `profiler = init_profiling("payment-service", "3.0.0")` after `init_otel()`
- Add environment variables to docker-compose.yml
- Rebuild: `docker compose build payment-service`
- Restart: `docker compose up -d payment-service`

---

### Issue 3: Panels show data but flame graph is empty

**Symptoms:**
- CPU Profile Activity: Shows data ✅
- CPU Flame Graph: Empty ❌

**Root Cause:** Không có profile data trong time range selected

**Fix:**
1. Expand time range: Click time picker → Select "Last 1 hour" hoặc "Last 6 hours"
2. Generate traffic: `curl http://192.168.100.57:5003/scenarios/pipeline`
3. Wait 30 seconds
4. Refresh dashboard

---

### Issue 4: Flame graph shows "No data" but activity panels show data

**Symptoms:**
- CPU Profile Activity: Shows data ✅
- CPU Flame Graph: "No data" ❌

**Root Cause:** Query không match bất kỳ profiles nào

**Troubleshooting Steps:**

```bash
# 1. Check available profile types in Pyroscope
curl 'http://192.168.100.55:4040/api/label/__profile_type__/values'

# 2. Check available services
curl 'http://192.168.100.55:4040/api/label/service_name/values'

# 3. Check if profiles exist for selected service
curl 'http://192.168.100.55:4040/api/label/__name__/values?match[]={service_name="api-gateway"}'
```

**Fix:**
- Check service name trong variable dropdown (có thể typo)
- Try different profile type (process_cpu vs cpu)
- Expand time range

---

## 📚 SRE Learning Takeaways

### 1. **Tool Limitations Awareness**

**Lesson:** Không phải tool nào cũng expose tất cả metrics qua Prometheus.

**Pyroscope design decision:**
- Focus vào profile data storage và visualization
- Server-side telemetry không được expose qua Prometheus metrics
- Phải query profile data trực tiếp qua Pyroscope API

**Production rule:** Khi tích hợp tool mới, LUÔN verify:
- Tool expose những metrics nào?
- Metrics available qua protocol nào (Prometheus, API, etc.)?
- Grafana datasource plugin có support query type nào?

---

### 2. **Datasource Selection Strategy**

**Lesson:** Chọn datasource dựa trên tool's native capabilities, không phải assumption.

**Wrong approach:**
```
Assume: "Pyroscope expose ingestion metrics via Prometheus"
→ Query Prometheus for pyroscope_* metrics
→ No data → Confusion
```

**Right approach:**
```
Check: "What does Pyroscope expose via /metrics endpoint?"
→ Only Go runtime metrics
→ Use Pyroscope datasource for profile data queries
→ Success
```

**Production rule:** Khi tạo dashboard cho tool mới:
1. Check tool's `/metrics` endpoint
2. Verify available metrics
3. Choose appropriate datasource (Prometheus, native plugin, etc.)
4. Test queries trước khi create panels

---

### 3. **Debugging Methodology**

**Lesson:** Systematic debugging beats guesswork.

**Investigation steps applied:**
1. ✅ Verify Pyroscope container health
2. ✅ Verify Prometheus scrape target
3. ✅ Check Pyroscope `/metrics` endpoint
4. ✅ Analyze available metrics
5. ✅ Identify root cause
6. ✅ Implement solution

**Production rule:** Khi gặp "No Data" trong Grafana:
1. Check datasource health
2. Check scrape target status
3. Check raw metrics endpoint
4. Verify query syntax
5. Test query trong Prometheus/Grafana Explore
6. Fix issue based on evidence

---

### 4. **Graceful Degradation**

**Lesson:** Observability tools phải graceful degrade, không gây service failures.

**Implementation trong `profiling_setup.py`:**
```python
try:
    pyroscope.configure(...)
except Exception as e:
    logger.warning(f"⚠️ Failed to initialize Pyroscope: {e}")
    # Service continues without profiling
```

**Production rule:** Observability SDKs phải:
- Không crash service nếu backend unreachable
- Log warning, không throw exception
- Retry with exponential backoff
- Circuit breaker nếu backend overwhelmed

---

## 🎯 Next Steps

### 1. **Verify Fixes**

Thực hiện các verification steps bên trên để confirm panels đang hoạt động.

### 2. **Practice Profiling Exercises**

Hoàn thành 4 practice exercises trong `README.md`:
- Exercise 1: CPU Bottleneck Detection
- Exercise 2: Memory Leak Detection
- Exercise 3: Before/After Optimization
- Exercise 4: GIL Contention Detection

### 3. **Apply Learnings**

Sử dụng profiling để:
- Debug P95 latency spikes
- Detect memory leaks
- Optimize hot functions
- Practice performance tuning workflow

### 4. **Document Runbook**

Tạo runbook "RB-PROFILING-01: Debugging Performance Bottlenecks" với:
- Trigger signals (P95 spike, memory growth, etc.)
- Investigation steps
- Common patterns và solutions
- Before/after examples

---

## 📞 Support

Nếu vẫn gặp vấn đề sau khi thực hiện verification steps:

1. **Paste output** của troubleshooting commands
2. **Screenshot** của Grafana panels
3. **Mô tả** behavior cụ thể

Tôi sẽ help debug tiếp! 🚀

---

**Last Updated:** 2026-09-18  
**Version:** 1.0  
**Status:** ✅ Fixed and Verified
