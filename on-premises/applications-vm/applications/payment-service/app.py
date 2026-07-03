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

# ============================================================
# Redis Idempotency Store (Fix Bom #1)
# ============================================================
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
ENABLE_REDIS = os.getenv("ENABLE_REDIS", "true").lower() == "true"
redis_client = redis.from_url(REDIS_URL, decode_responses=True) if ENABLE_REDIS else None

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
        # Log warning nhưng trả về True để Health Check pass (HTTP 200)
        # Tránh việc ECS Fargate kill task liên tục do thiếu Redis ở Phase 1
        logger.warning(f"Redis is unavailable: {e}. Degrading gracefully (Idempotency disabled).")
        return True 

# Truyền hàm đã wrap vào thay vì lambda raw
_health_checks = {"redis": redis_health_check} if redis_client else {}
health_bp = create_health_blueprint("payment-service", checks=_health_checks)
app.register_blueprint(health_bp)

# Hàm gọi Gateway giả lập qua HTTP thật (để test timeout)
@payment_breaker
def call_external_gateway(provider, delay):
    """
    Gọi ra external API. Dùng httpbin.org để simulate network delay.
    Nếu delay > timeout, requests sẽ ném exception -> Trigger Circuit Breaker.
    """
    # Dùng httpbin.org/delay/{n} để simulate gateway phản hồi chậm
    url = f"https://httpbin.org/delay/{int(delay)}" 
    
    # BẮT BUỘC: Connect timeout 2s, Read timeout 5s
    # Nếu httpbin mất 6s để trả lời, code sẽ không bị block vô hạn!
    response = requests.get(url, timeout=(2.0, 5.0)) 
    response.raise_for_status()
    return True

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

    # --- BƯỚC 1: IDEMPOTENCY CHECK (THE SHIELD) ---
    idempotency_key = f"idempotency:payment:{order_id}"
    if redis_client:
        # SET NX: Chỉ set nếu key CHƯA TỒN TẠI. EX: Tự động xóa sau 24h (86400s)
        is_new_transaction = redis_client.set(idempotency_key, "processing", nx=True, ex=86400)

        if not is_new_transaction:
            # Request trùng lặp! User bấm retry hoặc Network retry.
            logger.warning("Idempotency check failed: Duplicate request", extra={"order_id": order_id})
            return jsonify({
                "status": "idempotent_hit",
                "message": "Transaction already processed or in progress",
                "order_id": order_id
            }), 200 # Trả về 200 để client không bị lỗi, nhưng không trừ tiền

    # --- BƯỚC 2: TRACE & GATEWAY CALL ---
    with tracer.start_as_current_span("call_payment_gateway") as span:
        # Enrich Trace (Fix Bom #4): Gắn order_id vào span để debug trên X-Ray
        span.set_attribute("app.order_id", order_id)
        span.set_attribute("app.provider", provider)
        
        delay = random.uniform(0.5, 1.5)
        is_slow = random.random() < SLOW_RATE
        if is_slow:
            delay = random.uniform(3.0, 6.0) # Cố tình làm chậm > 5s để test Timeout
            span.set_attribute("app.slow", True)

        start_time = time.time()
        try:
            # Gọi qua Circuit Breaker
            call_external_gateway(provider, delay)
            
            # Simulate Business Failure (10% chance)
            if random.random() < FAILURE_RATE:
                raise Exception("Gateway rejected card")

        except requests.exceptions.Timeout:
            logger.error("Gateway Timeout", extra={"order_id": order_id})
            # Xóa key Redis để user có thể retry lại (vì giao dịch chưa hoàn tất)
            if redis_client:
                redis_client.delete(idempotency_key) 
            return problem_response(504, "Gateway Timeout", "Payment gateway took too long", instance="/charge")
            
        except pybreaker.CircuitBreakerError:
            logger.error("Circuit Breaker OPEN", extra={"order_id": order_id})
            if redis_client:
                redis_client.delete(idempotency_key)
            return problem_response(503, "Service Unavailable", "Payment gateway is down (Circuit Open)", instance="/charge")
            
        except Exception as e:
            logger.error("Payment failed", extra={"order_id": order_id, "error": str(e)})
            if redis_client:
                redis_client.delete(idempotency_key)
            return problem_response(500, "Payment Error", str(e), instance="/charge")

        duration = time.time() - start_time
        gateway_duration.record(duration, {"provider": provider})

    # --- BƯỚC 3: SUCCESS ---
    txn_id = f"txn-{random.randint(10000, 99999)}"
    
    # Cập nhật Redis: Đánh dấu giao dịch đã HOÀN TẤT
    if redis_client:
        redis_client.set(idempotency_key, txn_id, ex=86400)
    
    # Enrich span với txn_id
    span.set_attribute("app.transaction_id", txn_id)

    payments_counter.add(1, {"status": "success", "provider": provider})
    payment_amount.record(amount, {"status": "success", "provider": provider})

    return jsonify({
        "status": "success",
        "order_id": order_id,
        "transaction_id": txn_id,
        "provider": provider,
        "amount": amount,
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5002)
