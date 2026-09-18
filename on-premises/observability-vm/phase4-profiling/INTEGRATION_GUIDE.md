# 🔧 Integration Guide: Adding Profiling to Order Service

This guide shows exactly how to integrate Pyroscope profiling into the `order-service` as a reference implementation.

---

## Step 1: Update `requirements.txt`

Add Pyroscope SDK to the dependencies:

```txt
# applications-vm/applications/order-service/requirements.txt

flask==3.1.*
gunicorn==23.0.*
requests==2.32.*
opentelemetry-api==1.33.*
opentelemetry-sdk==1.33.*
opentelemetry-exporter-otlp-proto-grpc==1.33.*
opentelemetry-instrumentation-flask==0.54b0
opentelemetry-instrumentation-requests==0.54b0
opentelemetry-instrumentation-logging==0.54b0
opentelemetry-instrumentation-psycopg2==0.54b0
opentelemetry-instrumentation-redis==0.54b0
python-json-logger==3.2.*
psycopg2-binary==2.9.*
redis==5.2.*
confluent-kafka==2.6.*

# 🆕 Add this line for continuous profiling
grafana-pyroscope>=0.8.0
```

---

## Step 2: Update `app.py`

Initialize profiling after OTel initialization:

```python
# applications-vm/applications/order-service/app.py

"""
============================================================
Order Service — Phase 5 + Shared Refactor + Profiling
============================================================
"""

import os
import time
import json
import random
import uuid
import requests
from confluent_kafka import Producer as KafkaProducer
from flask import Flask, jsonify, request as flask_request
from shared.errors import problem_response, map_order_status_to_http

# ----------------------------------------------------------
# Shared modules
# ----------------------------------------------------------
from shared.logging_config import setup_logging
from shared.otel_setup import init_otel
from shared.db_utils import DatabasePool, RedisCache, retry_connect
from shared.health import create_health_blueprint
from shared.errors import problem_response
from shared.shutdown_handler import shutdown_manager
from shared.otel_watchdog import start_otel_watchdog

# 🆕 Add this import for profiling
from shared.profiling_setup import init_profiling

# ----------------------------------------------------------
# Auto-instrumentation imports
# ----------------------------------------------------------
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.propagate import inject
from opentelemetry.metrics import Observation

# ----------------------------------------------------------
# Initialize logging + OTel
# ----------------------------------------------------------
logger = setup_logging("order-service")
tracer, meter = init_otel("order-service", "3.0.0")

# 🆕 Initialize profiling (AFTER init_otel)
# This returns the pyroscope module if profiling is enabled, None otherwise
profiler = init_profiling("order-service", "3.0.0")

# Auto-instrumentation BEFORE creating connections
Psycopg2Instrumentor().instrument()
RedisInstrumentor().instrument()

# ... rest of the code remains the same ...
```

---

## Step 3: (Optional) Add Profiling to Specific Functions

If you want to add custom tags to specific functions for better filtering:

```python
@app.route("/process", methods=["POST"])
def process_order():
    """Process a new order."""
    
    # 🆕 Add custom profiling context for this operation
    if profiler:
        with profiler.tag_wrapper({
            "operation": "create_order",
            "endpoint": "/process"
        }):
            return _process_order_impl()
    else:
        return _process_order_impl()

def _process_order_impl():
    """Actual order processing logic."""
    # ... existing code ...
    pass
```

---

## Step 4: Rebuild and Restart

```bash
cd applications-vm/applications

# Rebuild the image with new dependencies
docker compose build order-service

# Restart the service
docker compose up -d order-service

# Verify profiling is enabled
docker compose logs order-service | grep "Profiling enabled"
# Expected: ✅ Profiling enabled for order-service
#           Pyroscope URL: http://pyroscope:4040
#           Sample Rate: 100 Hz
```

---

## Step 5: Generate Traffic and View Profiles

```bash
# Generate some orders
curl -X POST http://localhost:5000/order \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}'

# Or run the traffic generator
curl http://localhost:5003/scenarios/pipeline
```

Then open Pyroscope UI:
```
http://localhost:4040
```

Select **order-service** from the dropdown and explore the flame graph!

---

## Step 6: Verify Integration

### Check Profiling Data is Flowing

```bash
# Check Pyroscope server is receiving data
curl http://localhost:4040/ready
# Expected: "ready"

# Check if order-service is sending profiles
docker compose logs pyroscope | grep "order-service"
# Expected: Ingestion logs showing data from order-service
```

### Check Grafana Datasource

1. Open Grafana: http://localhost:3000
2. Go to **Explore**
3. Select **Pyroscope** as datasource
4. Query: `{app_name="order-service"}`
5. You should see flame graphs

---

## 🔍 Troubleshooting

### Problem: "Pyroscope SDK not installed"

**Solution:**
```bash
# Rebuild the image to install new dependencies
docker compose build --no-cache order-service
docker compose up -d order-service
```

### Problem: "Failed to initialize Pyroscope"

**Possible causes:**
1. Pyroscope server is not running
2. Network connectivity issue
3. Pyroscope URL is incorrect

**Solution:**
```bash
# Check if Pyroscope is running
docker compose -f ../observability-vm/phase4-profiling/docker-compose.yml ps

# Check network connectivity
docker compose exec order-service curl http://pyroscope:4040/ready
# Expected: "ready"

# Check environment variables
docker compose exec order-service env | grep PYROSCOPE
# Expected: PYROSCOPE_URL=http://pyroscope:4040
```

### Problem: No profiles appearing in Pyroscope UI

**Possible causes:**
1. No traffic generated
2. Profiling disabled (`ENABLE_PROFILING=false`)
3. Service not restarted after adding profiling

**Solution:**
```bash
# Generate traffic
curl http://localhost:5003/scenarios/pipeline

# Check if profiling is enabled
docker compose logs order-service | grep "Profiling"
# Expected: ✅ Profiling enabled for order-service

# Restart service
docker compose restart order-service
```

---

## 📊 What You'll See in Pyroscope

### CPU Profile

Shows which functions consume the most CPU time:

```
┌─────────────────────────────────────────────────────────┐
│  ██████████████████████████████████████  process_order  │  45%
│  ████████████████████  db_query                         │  25%
│  ████████████  redis_get                                │  15%
│  ████████  kafka_produce                                │  10%
│  ████  json_serialize                                   │   5%
└─────────────────────────────────────────────────────────┘
```

**Interpretation:**
- `process_order` is the hot path (45% of CPU time)
- Optimize this function first for maximum impact

### Memory Allocation Profile

Shows which functions allocate the most memory:

```
┌─────────────────────────────────────────────────────────┐
│  ████████████████████████████████████  create_order_obj │  60%
│  ████████████████  serialize_response                   │  25%
│  ████████  parse_request                                │  15%
└─────────────────────────────────────────────────────────┘
```

**Interpretation:**
- `create_order_obj` allocates most memory
- Check for memory leaks or inefficient object creation

---

## 🎯 Next Steps

After successfully integrating profiling into `order-service`:

1. **Apply to other services:**
   - `payment-service`
   - `api-gateway`
   - `notification-worker`
   - `inventory-worker`

2. **Create practice exercises:**
   - Add `/stress/cpu` endpoint
   - Add `/stress/memory` endpoint
   - Measure before/after optimizations

3. **Build Grafana dashboards:**
   - Link traces to profiles
   - Create profiling overview dashboard

4. **Set up alerts:**
   - Profiling overhead > 5%
   - No profiling data for service (5m)

---

## 📚 References

- [Phase 4.5 README](../README.md) - Full learning guide
- [Pyroscope Documentation](https://grafana.com/docs/pyroscope/)
- [shared/profiling_setup.py](../../applications-vm/applications/shared/profiling_setup.py) - SDK wrapper code
