# 🔬 Phase 4.5: Continuous Profiling with Pyroscope

> **Continuous Profiling** — the 4th pillar of observability — giúp bạn trả lời câu hỏi: *"Tại sao code lại chậm/tốn RAM ở dòng nào?"*

---

## 📚 Learning Objectives

Sau khi hoàn thành Phase 4.5, bạn sẽ nắm được:

| # | Knowledge Area | Skills Gained |
|---|---|---|
| 1 | **Continuous Profiling as 4th Pillar** | Understand how profiles complement metrics, logs, and traces |
| 2 | **Flame Graph Interpretation** | Read flame graphs to identify hot functions and bottlenecks |
| 3 | **Sampling Strategies** | Balance profiling detail vs CPU overhead (100Hz vs 1000Hz) |
| 4 | **Python SDK Integration** | Instrument Flask/Python services with Pyroscope SDK |
| 5 | **Performance Optimization Workflow** | Inject bottleneck → profile → optimize → verify improvement |
| 6 | **Grafana Integration** | Link traces to profiles, create profiling dashboards |
| 7 | **Production Guardrails** | Feature flags, overhead monitoring, graceful degradation |
| 8 | **eBPF Profiling (Advanced)** | Zero-instrumentation profiling with Parca (optional) |

---

## 🏗️ Architecture Overview

### The 4 Pillars of Observability

```
┌─────────────────────────────────────────────────────────────────┐
│                    Observability Stack                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  METRICS     │  │   LOGS       │  │   TRACES     │          │
│  │  Prometheus  │  │   Loki       │  │   Tempo      │          │
│  │              │  │              │  │              │          │
│  │  "What       │  │  "Why did    │  │  "Where did  │          │
│  │   happened?" │  │   it happen?"│  │   it happen?"│          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│                           ▼                                     │
│              ┌────────────────────────┐                        │
│              │    PROFILES (NEW)      │                        │
│              │      Pyroscope         │                        │
│              │                        │                        │
│              │  "What code caused     │                        │
│              │   it to happen?"       │                        │
│              └────────────────────────┘                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Applications VM (192.168.100.57)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Order Service  │  │ Payment Service │  │  API Gateway    │ │
│  │                 │  │                 │  │                 │ │
│  │  ┌───────────┐  │  │  ┌───────────┐  │  │  ┌───────────┐  │ │
│  │  │ Pyroscope │  │  │  │ Pyroscope │  │  │  │ Pyroscope │  │ │
│  │  │ SDK       │  │  │  │ SDK       │  │  │  │ SDK       │  │ │
│  │  └─────┬─────┘  │  │  └─────┬─────┘  │  │  └─────┬─────┘  │ │
│  │        │        │  │        │        │  │        │        │ │
│  └────────┼────────┘  └────────┼────────┘  └────────┼────────┘ │
│           │                    │                    │          │
└───────────┼────────────────────┼────────────────────┼──────────┘
            │                    │                    │
            └────────────────────┼────────────────────┘
                                 │
                                 │ OTLP/HTTP (profiles)
                                 │ Port 4040
                                 │
┌────────────────────────────────┼──────────────────────────────┐
│                    Observability VM (192.168.100.55)           │
├────────────────────────────────┼──────────────────────────────┤
│                                │                              │
│                                ▼                              │
│                      ┌─────────────────┐                     │
│                      │   Pyroscope     │                     │
│                      │   Server        │                     │
│                      │   :4040         │                     │
│                      └────────┬────────┘                     │
│                               │                              │
│                               ▼                              │
│                      ┌─────────────────┐                     │
│                      │   Grafana       │                     │
│                      │   (Datasource)  │                     │
│                      └────────┬────────┘                     │
│                               │                              │
│                               ▼                              │
│                    ┌─────────────────────┐                   │
│                    │  Flame Graphs       │                   │
│                    │  Profile Explorer   │                   │
│                    │  Dashboards         │                   │
│                    └─────────────────────┘                   │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Step 1: Deploy Pyroscope Server

```bash
cd observability-vm/phase4-profiling
docker compose up -d
```

**Verify:**
```bash
docker compose ps
# Expected: pyroscope container running

curl http://localhost:4040/ready
# Expected: "ready"
```

### Step 2: Configure Grafana Datasource

```bash
cd observability-vm/phase4-profiling/scripts
bash setup.sh
```

**What this does:**
1. Copies `pyroscope.yml` to Grafana's provisioning directory
2. Restarts Grafana to load the new datasource
3. Verifies the datasource is configured

**Verify:**
1. Open Grafana: http://localhost:3000
2. Go to **Configuration → Data Sources**
3. You should see **Pyroscope** in the list

### Step 3: Instrument Python Services

Add Pyroscope SDK to `requirements.txt` of each service:

```txt
# requirements.txt (add this line)
grafana-pyroscope>=0.8.0
```

Update `app.py` to initialize profiling:

```python
# app.py (add after init_otel)
from shared.profiling_setup import init_profiling

# Initialize profiling
profiler = init_profiling("order-service", "3.0.0")
```

**Rebuild and restart:**
```bash
cd applications-vm/applications
docker compose build order-service
docker compose up -d order-service
```

### Step 4: Generate Traffic & View Profiles

1. Generate some traffic:
```bash
curl http://localhost:5003/scenarios/pipeline
```

2. Open Pyroscope UI: http://localhost:4040

3. Select **order-service** from the dropdown

4. Explore the flame graph!

---

## 🔥 Practice Exercises

### Exercise 1: CPU Bottleneck Detection

**Objective:** Detect a CPU-intensive function using flame graphs.

**Setup:**
```python
# In order-service/app.py, add this endpoint:
@app.route("/stress/cpu")
def stress_cpu():
    """Simulate CPU-intensive operation."""
    result = 0
    for i in range(10_000_000):
        result += i * i
    return jsonify({"result": result})
```

**Steps:**
1. Call the endpoint: `curl http://localhost:5001/stress/cpu`
2. Open Pyroscope UI
3. Select **order-service**
4. Filter by time range (last 5 minutes)
5. Look for the `stress_cpu` function in the flame graph

**What you'll see:**
- `stress_cpu` takes up ~90% of the flame graph width
- This indicates it's consuming most of the CPU time

**SRE Insight:**
- Flame graph width = percentage of CPU time
- Wider = more CPU-intensive
- This is how you identify hot paths in production

---

### Exercise 2: Memory Leak Detection

**Objective:** Detect memory allocation patterns that indicate a leak.

**Setup:**
```python
# In order-service/app.py, add this endpoint:
LEAKY_CACHE = []

@app.route("/stress/memory")
def stress_memory():
    """Simulate memory leak by accumulating objects."""
    for i in range(1000):
        LEAKY_CACHE.append({"data": "x" * 1000})  # 1KB each
    return jsonify({"cache_size": len(LEAKY_CACHE)})
```

**Steps:**
1. Call the endpoint multiple times: `for i in {1..10}; do curl http://localhost:5001/stress/memory; done`
2. Open Pyroscope UI
3. Select **Memory Allocation** profile type
4. Look for `stress_memory` in the flame graph

**What you'll see:**
- `stress_memory` dominates the memory allocation profile
- `LEAKY_CACHE.append()` is the hot path

**SRE Insight:**
- Memory allocation profiles show where objects are created
- If a function consistently allocates without freeing, it's a leak candidate
- Production: Monitor memory growth rate over time to detect leaks

---

### Exercise 3: Before/After Optimization

**Objective:** Measure performance improvement with flame graphs.

**Setup (Before):**
```python
@app.route("/slow-query")
def slow_query():
    """Simulate slow database query."""
    time.sleep(2)  # Artificial delay
    return jsonify({"status": "ok"})
```

**Steps:**
1. Call the endpoint: `curl http://localhost:5001/slow-query`
2. Open Pyroscope UI
3. Note the time spent in `slow_query` (should be ~2 seconds)

**Optimize:**
```python
@app.route("/slow-query")
def slow_query():
    """Optimized: add caching."""
    # Simulate cache hit
    cached = redis_client.get("slow_query_result")
    if cached:
        return jsonify({"status": "ok", "cached": True})
    
    # Cache miss: do the slow operation
    time.sleep(2)
    result = {"status": "ok"}
    redis_client.setex("slow_query_result", 60, json.dumps(result))
    return jsonify(result)
```

**Steps (After):**
1. Call the endpoint twice (first = cache miss, second = cache hit)
2. Open Pyroscope UI
3. Compare the flame graphs

**What you'll see:**
- First call: `slow_query` takes ~2 seconds
- Second call: `slow_query` takes ~50ms (cache hit)

**SRE Insight:**
- Flame graphs provide visual proof of optimization
- Production: Use this to justify refactoring efforts to stakeholders
- Document: Save before/after flame graphs in post-mortems

---

### Exercise 4: GIL Contention Detection

**Objective:** Detect Python GIL contention in multi-threaded code.

**Setup:**
```python
import threading

@app.route("/stress/gil")
def stress_gil():
    """Simulate GIL contention with CPU-bound threads."""
    results = []
    
    def cpu_bound_task():
        total = 0
        for i in range(5_000_000):
            total += i
        results.append(total)
    
    # Spawn 4 threads (all competing for GIL)
    threads = [threading.Thread(target=cpu_bound_task) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    
    return jsonify({"results": results})
```

**Steps:**
1. Call the endpoint: `curl http://localhost:5001/stress/gil`
2. Open Pyroscope UI
3. Look for `cpu_bound_task` in the flame graph
4. Check the "Lock Contention" profile type (if available)

**What you'll see:**
- 4 threads all running `cpu_bound_task`
- Total time > time for single thread (due to GIL serialization)

**SRE Insight:**
- Python GIL prevents true parallelism for CPU-bound threads
- For CPU-bound workloads, use `multiprocessing` instead of `threading`
- Production: Monitor GIL contention to decide between sync/async/gevent workers

---

## 📊 Grafana Dashboard Integration

### Link Traces to Profiles

When you see a slow trace in Tempo, you can jump directly to the flame graph:

1. Open **Explore → Tempo**
2. Search for a slow trace
3. Click on a span
4. Look for **"View Profile"** link (if exemplars are configured)

### Create Profiling Dashboard

Create a new Grafana dashboard with these panels:

| Panel | Query | Purpose |
|-------|-------|---------|
| **CPU Usage by Function** | `{app_name="order-service"}` | Identify hot functions |
| **Memory Allocation** | `{app_name="order-service", profile_type="memory"}` | Detect memory leaks |
| **Profile Overhead** | `pyroscope_profiling_cpu_seconds_total` | Monitor profiling overhead |

---

## 🛡️ Production Guardrails

### 1. Sampling Rate Control

```bash
# Environment variable to control sampling rate
PYROSCOPE_SAMPLE_RATE=100  # Default: 100 Hz (~1-2% CPU overhead)

# Reduce overhead in production
PYROSCOPE_SAMPLE_RATE=50   # 50 Hz (~0.5-1% CPU overhead)

# Increase detail for debugging
PYROSCOPE_SAMPLE_RATE=200  # 200 Hz (~2-4% CPU overhead)
```

**Rule of thumb:**
- Lab/Development: 100-200 Hz
- Production (normal): 50-100 Hz
- Production (incident): 200 Hz (temporary)

### 2. Feature Flag

```bash
# Disable profiling completely
ENABLE_PROFILING=false

# Enable profiling
ENABLE_PROFILING=true  # Default
```

**Use cases:**
- Disable during incidents (if profiling causes overhead)
- A/B test performance with/without profiling
- Gradual rollout in production

### 3. Overhead Monitoring

Monitor these metrics to ensure profiling doesn't impact performance:

```promql
# Pyroscope SDK overhead
pyroscope_profiling_cpu_seconds_total / process_cpu_seconds_total > 0.05

# Alert if profiling overhead > 5%
- alert: ProfilingOverheadHigh
  expr: |
    rate(pyroscope_profiling_cpu_seconds_total[5m])
    / rate(process_cpu_seconds_total[5m]) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Profiling overhead > 5%"
```

### 4. Graceful Degradation

The `profiling_setup.py` module implements graceful degradation:

- If Pyroscope SDK is not installed → profiling disabled, service runs normally
- If Pyroscope server is unreachable → log warning, service runs normally
- If profiling causes errors → catch exception, service runs normally

**Rule:** Observability should NEVER cause service failures.

---

## 🔬 Advanced: eBPF Profiling with Parca (Optional)

### What is eBPF Profiling?

**eBPF (Extended Berkeley Packet Filter)** allows profiling at the kernel level with zero instrumentation.

**Pros:**
- Zero code changes required
- Profiles kernel functions, syscalls, and user-space code
- Very low overhead (< 1% CPU)

**Cons:**
- Requires Linux kernel 4.9+
- Needs root privileges (or `CAP_BPF` + `CAP_SYS_ADMIN`)
- Less granular than SDK-based profiling (no line numbers)

### Setup Parca Agent (Optional)

```bash
# Add to phase4-profiling/docker-compose.yml
parca-agent:
  image: ghcr.io/parca-dev/parca-agent:v0.33.0
  container_name: parca-agent
  privileged: true
  pid: host
  volumes:
    - /:/host:ro
    - /sys:/sys:ro
    - /proc:/proc:ro
  environment:
    - PARCA_AGENT_REMOTE_STORE_ADDRESS=parca:7070
  networks:
    - observability
```

**Learning value:**
- Understand eBPF and kernel-level observability
- Compare SDK vs eBPF profiling approaches
- Production: Use eBPF for workloads you can't instrument (legacy, third-party)

---

## 📚 References & Further Reading

| Resource | URL | Focus |
|----------|-----|-------|
| Pyroscope Documentation | https://grafana.com/docs/pyroscope/ | Official docs |
| Flame Graph Explanation | https://www.brendangregg.com/flamegraphs.html | Brendan Gregg's guide |
| Continuous Profiling Blog | https://grafana.com/blog/2022/08/04/continuous-profiling/ | Grafana Labs |
| eBPF.io | https://ebpf.io/ | eBPF fundamentals |

---

## ✅ Checklist

- [ ] Pyroscope server deployed (`docker compose up -d`)
- [ ] Grafana datasource configured (`bash setup.sh`)
- [ ] Pyroscope SDK added to `requirements.txt`
- [ ] `init_profiling()` called in `app.py`
- [ ] Traffic generated and profiles visible
- [ ] Exercise 1: CPU bottleneck detected
- [ ] Exercise 2: Memory leak detected
- [ ] Exercise 3: Before/after optimization measured
- [ ] Exercise 4: GIL contention detected (optional)
- [ ] Grafana dashboard created
- [ ] Production guardrails understood (sampling, feature flags, overhead)

---

## 🎓 SRE Takeaways

| Concept | Application in Production |
|---------|---------------------------|
| **4th Pillar** | Profiles answer "what code caused it?" — essential for performance debugging |
| **Flame Graphs** | Visual representation of CPU/memory usage by function — intuitive and powerful |
| **Sampling Rate** | Balance detail vs overhead — 100 Hz is production-safe, 1000 Hz is for debugging only |
| **Feature Flags** | Always have a kill switch for observability tools — they should never cause outages |
| **Graceful Degradation** | Observability failures should not impact service availability |
| **eBPF** | Zero-instrumentation profiling — great for legacy workloads or when you can't modify code |

---

**Next Phase:** Phase 5 — Integration + Chaos Testing + SLO + DR Drill

You now have the 4th pillar of observability. Use it to debug performance bottlenecks, optimize hot paths, and make data-driven decisions about code quality.
