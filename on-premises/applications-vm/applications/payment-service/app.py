"""
============================================================
Payment Service — Phase 5 + Shared Refactor
============================================================
Xử lý thanh toán. Simulate delays và random errors.
Metrics: payments counter, amount histogram, gateway duration

Endpoints:
  - POST /charge      → process payment
  - GET  /health      → readiness check (alias)
  - GET  /health/live → liveness check
  - GET  /health/ready → readiness check
============================================================
"""

import os
import time
import random
import redis
import requests
import pybreaker
from flask import Flask, jsonify, request

# Shared modules
from shared.logging_config import setup_logging
from shared.otel_setup import init_otel
from shared.health import create_health_blueprint
from shared.errors import problem_response
from shared.shutdown_handler import shutdown_manager
from shared.idempotency import IdempotencyGuard
from shared.otel_watchdog import start_otel_watchdog # add watchdog
# Auto-instrumentation
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Initialize logging + OTel
logger = setup_logging("payment-service")
tracer, meter = init_otel("payment-service", "2.0.0")

# Auto-instrument outgoing HTTP requests (Fix Bom #4)
RequestsInstrumentor().instrument()

# ============================================================
# Custom Metrics
# ============================================================
payments_counter = meter.create_counter(name="payments_total", description="Total payment transactions", unit="1")
payment_amount = meter.create_histogram(name="payment_amount_dollars", description="Payment amount", unit="$")
gateway_duration = meter.create_histogram(name="payment_gateway_duration_seconds", description="Gateway latency", unit="s")

ENABLE_CIRCUIT_BREAKER_METRICS = os.getenv("ENABLE_CIRCUIT_BREAKER_METRICS", "true").lower() == "true"

if ENABLE_CIRCUIT_BREAKER_METRICS:
    # Circuit Breaker State: 0=Closed, 1=Open, 2=Half-Open
    circuit_breaker_state = meter.create_gauge(
        name="payment_circuit_breaker_state",
        description="Circuit breaker state (0=Closed, 1=Open, 2=Half-Open)",
        unit="1"
    )
    circuit_breaker_transitions = meter.create_counter(
        name="payment_circuit_breaker_transitions_total",
        description="Number of circuit breaker state transitions",
        unit="1"
    )
    circuit_breaker_rejections = meter.create_counter(
        name="payment_circuit_breaker_rejections_total",
        description="Number of requests rejected by open circuit breaker",
        unit="1"
    )

# ============================================================
# Redis Idempotency Store (Fix Bom #1)
# ============================================================
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
ENABLE_REDIS = os.getenv("ENABLE_REDIS", "true").lower() == "true"
redis_client = redis.from_url(REDIS_URL, decode_responses=True) if ENABLE_REDIS else None

idempotency_guard = IdempotencyGuard(redis_client) if redis_client else None

def close_redis_on_shutdown():
    """Đóng Redis connections khi process tắt."""
    if redis_client:
        logger.info("Closing Redis connections...")
        redis_client.close()

shutdown_manager.register(
    callback=close_redis_on_shutdown,
    name="Redis Client",
    timeout_seconds=5
)

# ============================================================
# Circuit Breaker (Fix Bom #3)
# ============================================================
# Mở circuit nếu có 3 lỗi liên tiếp, đóng lại sau 30s
payment_breaker = pybreaker.CircuitBreaker(
    fail_max=3, 
    reset_timeout=30,
    name="payment_gateway_breaker"
)

PROVIDERS = ["stripe", "paypal", "square"]
FAILURE_RATE = float(os.getenv("PAYMENT_FAILURE_RATE", "0.10"))
SLOW_RATE = float(os.getenv("PAYMENT_SLOW_RATE", "0.20"))

# State mapping: pybreaker state → numeric value
STATE_MAP = {
    "closed": 0,      # Normal operation
    "open": 1,        # Rejecting all requests
    "half-open": 2    # Testing with 1 request
}

def get_breaker_state():
    """Convert pybreaker state to numeric value."""
    state_name = str(payment_breaker.state).lower()
    return STATE_MAP.get(state_name, 0)

def call_external_gateway_with_tracking(provider, delay):
    """
    Wrap circuit breaker call với state tracking và metrics emission.
    Consolidates failure simulation (fixes double-FAILURE_RATE bug).
    """
    if not ENABLE_CIRCUIT_BREAKER_METRICS:
        # Fallback: gọi qua CB nhưng không track metrics
        with payment_breaker:
            time.sleep(delay)
            if random.random() < FAILURE_RATE:
                raise Exception("Gateway rejected card")
        return True
    
    # Record state TRƯỚC khi call
    state_before = get_breaker_state()
    circuit_breaker_state.set(state_before, {"breaker": "payment_gateway"})
    
    try:
        with payment_breaker:
            time.sleep(delay)
            if random.random() < FAILURE_RATE:
                raise Exception("Gateway rejected card")
        
        # Record state SAU khi call
        state_after = get_breaker_state()
        circuit_breaker_state.set(state_after, {"breaker": "payment_gateway"})
        if state_before != state_after:
            circuit_breaker_transitions.add(1, {
                "breaker": "payment_gateway",
                "from_state": str(state_before),
                "to_state": str(state_after)
            })
        return True
        
    except pybreaker.CircuitBreakerError:
        circuit_breaker_rejections.add(1, {"breaker": "payment_gateway"})
        circuit_breaker_state.set(1, {"breaker": "payment_gateway"})  # OPEN
        raise


# ============================================================
# Flask App
# ============================================================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# 👇 FIX BOM #1: Graceful Degradation cho Redis
def redis_health_check():
    try:
        return redis_client.ping()
    except Exception as e:
        logger.warning(f"Redis is unavailable: {e}. Degrading gracefully (Idempotency disabled).")
        return True 

_health_checks = {"redis": redis_health_check} if redis_client else {}
health_bp = create_health_blueprint("payment-service", checks=_health_checks)
app.register_blueprint(health_bp)

@app.route("/charge", methods=["POST"])
def charge():
    if request.is_json:
        data = request.get_json()
        order_id = data.get("order_id", "unknown")
        amount = data.get("amount")
    else:
        order_id = request.args.get("order_id", "unknown")
        amount = request.args.get("amount")

    if not amount:
        amount = round(random.uniform(10.0, 500.0), 2)
    else:
        amount = float(amount)

    provider = random.choice(PROVIDERS)
    logger.info("Processing payment", extra={"order_id": order_id, "amount": amount, "provider": provider})

    # ────────────────────────────────────────────────────────────
    # 🛡️ BƯỚC 1: IDEMPOTENCY CHECK (THE SHIELD) — FIX BOMB #4
    # ────────────────────────────────────────────────────────────
    if idempotency_guard:
        status = idempotency_guard.acquire(order_id)
        
        if status == "blocked":
            # Request trùng lặp! Kiểm tra cached result
            cached_result = idempotency_guard.get_cached_result(order_id)
            
            if cached_result:
                # Transaction đã success trước đó → trả về cached result
                logger.warning(
                    "Idempotency hit: returning cached success",
                    extra={"order_id": order_id}
                )
                return jsonify(cached_result), 200
            else:
                # Transaction đang "processing" hoặc "failed"
                # Trả về 409 Conflict để client biết không nên retry ngay
                logger.warning(
                    "Idempotency hit: transaction in progress or failed",
                    extra={"order_id": order_id}
                )
                return jsonify({
                    "status": "in_progress",
                    "message": "Transaction is being processed, please wait 60s before retry",
                    "order_id": order_id,
                    "retry_after_seconds": 60
                }), 409
    
    # ────────────────────────────────────────────────────────────
    # BƯỚC 2: TRACE & GATEWAY CALL
    # ────────────────────────────────────────────────────────────
    with tracer.start_as_current_span("call_payment_gateway") as span:
        span.set_attribute("app.order_id", order_id)
        span.set_attribute("app.provider", provider)
        
        delay = random.uniform(0.5, 1.5)
        is_slow = random.random() < SLOW_RATE
        if is_slow:
            delay = random.uniform(3.0, 6.0)
            span.set_attribute("app.slow", True)
        
        start_time = time.time()
        
        try:
            # Gọi qua Circuit Breaker (with state tracking)
            call_external_gateway_with_tracking(provider, delay)
                
        except requests.exceptions.Timeout:
            duration = time.time() - start_time
            gateway_duration.record(duration, {"provider": provider})
            payments_counter.add(1, {
                "status": "failed", "provider": provider, "reason": "timeout"
            })
            logger.error("Gateway Timeout", extra={"order_id": order_id})
            if idempotency_guard:
                idempotency_guard.mark_failed(order_id, "Gateway Timeout")
            return problem_response(504, "Gateway Timeout", "Payment gateway took too long", instance="/charge")
            
        except pybreaker.CircuitBreakerError:
            payments_counter.add(1, {
                "status": "failed", "provider": provider, "reason": "circuit_open"
            })
            logger.error("Circuit Breaker OPEN", extra={"order_id": order_id})
            if idempotency_guard:
                idempotency_guard.mark_failed(order_id, "Circuit Breaker OPEN")
            return problem_response(503, "Service Unavailable", "Payment gateway is down (Circuit Open)", instance="/charge")
            
        except Exception as e:
            duration = time.time() - start_time
            gateway_duration.record(duration, {"provider": provider})
            payments_counter.add(1, {
                "status": "failed", "provider": provider, "reason": "gateway_rejected"
            })
            logger.error("Payment failed", extra={"order_id": order_id, "error": str(e)})
            if idempotency_guard:
                idempotency_guard.mark_failed(order_id, str(e))
            return problem_response(500, "Payment Error", str(e), instance="/charge")
        
        duration = time.time() - start_time
        gateway_duration.record(duration, {"provider": provider})
        
        # ────────────────────────────────────────────────────────────
        # BƯỚC 3: SUCCESS — Mark và cache result
        # ────────────────────────────────────────────────────────────
        txn_id = f"txn-{random.randint(10000, 99999)}"
        span.set_attribute("app.transaction_id", txn_id)
        
        payments_counter.add(1, {"status": "success", "provider": provider})
        payment_amount.record(amount, {"status": "success", "provider": provider})
        
        # 🆕 Build result dict
        result = {
            "status": "success",
            "order_id": order_id,
            "transaction_id": txn_id,
            "provider": provider,
            "amount": amount,
        }
        
        # 🆕 Mark as success với TTL 24h
        if idempotency_guard:
            idempotency_guard.mark_success(order_id, result)
        
        return jsonify(result)

if __name__ == "__main__":
    # Background thread: emit CB state mỗi 10s để Grafana không show "No Data" khi idle
    if ENABLE_CIRCUIT_BREAKER_METRICS:
        import threading
        def emit_circuit_breaker_state_periodically():
            while True:
                state = get_breaker_state()
                circuit_breaker_state.set(state, {"breaker": "payment_gateway"})
                time.sleep(10)
        threading.Thread(
            target=emit_circuit_breaker_state_periodically,
            daemon=True,
            name="circuit-breaker-metrics"
        ).start()
    
    # Chỉ chạy watchdog khi app thực sự chạy (tránh chạy 2 lần do Flask reloader)
    start_otel_watchdog(interval=30, max_failures=3)
    app.run(host="0.0.0.0", port=5002)
