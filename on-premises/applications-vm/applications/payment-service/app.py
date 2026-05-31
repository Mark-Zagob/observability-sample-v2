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
from flask import Flask, jsonify, request

# ----------------------------------------------------------
# Shared modules
# ----------------------------------------------------------
from shared.logging_config import setup_logging
from shared.otel_setup import init_otel
from shared.health import create_health_blueprint
from shared.errors import problem_response

# ----------------------------------------------------------
# Auto-instrumentation imports
# ----------------------------------------------------------
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# ----------------------------------------------------------
# Initialize logging + OTel
# ----------------------------------------------------------
logger = setup_logging("payment-service")
tracer, meter = init_otel("payment-service", "2.0.0")

# ============================================================
# Custom Metrics
# ============================================================
payments_counter = meter.create_counter(
    name="payments_total",
    description="Total payment transactions",
    unit="1",
)

payment_amount = meter.create_histogram(
    name="payment_amount_dollars",
    description="Payment amount distribution in dollars",
    unit="$",
)

gateway_duration = meter.create_histogram(
    name="payment_gateway_duration_seconds",
    description="External payment gateway call duration",
    unit="s",
)

# ============================================================
# Flask App
# ============================================================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# Simulated payment providers
PROVIDERS = ["stripe", "paypal", "square"]

# --- Health checks (no external deps to check) ---
health_bp = create_health_blueprint("payment-service")
app.register_blueprint(health_bp)

FAILURE_RATE = float(os.getenv("PAYMENT_FAILURE_RATE", "0.10")) # Mặc định 10% lỗi
SLOW_RATE = float(os.getenv("PAYMENT_SLOW_RATE", "0.20"))  # Mặc định 20% chậm

@app.route("/charge", methods=["POST"])
def charge():
    """Xử lý thanh toán"""
    # Support both JSON body (preferred) and query params (backward compat)
    if request.is_json:
        data = request.get_json()
        order_id = data.get("order_id", "unknown")
        amount = data.get("amount")
    else:
        order_id = request.args.get("order_id", "unknown")
        amount = request.args.get("amount")

    if amount:
        amount = float(amount)
    else:
        amount = round(random.uniform(10.0, 500.0), 2)

    provider = random.choice(PROVIDERS)

    logger.info("Processing payment",
                 extra={"order_id": order_id, "amount": amount, "provider": provider})

    # Step 1: Validate payment method
    with tracer.start_as_current_span("validate_payment_method") as span:
        time.sleep(random.uniform(0.01, 0.03))
        span.set_attribute("payment.order_id", order_id)
        span.set_attribute("payment.provider", provider)
        span.set_attribute("payment.amount", amount)

    # Step 2: Call external payment gateway
    with tracer.start_as_current_span("call_payment_gateway") as span:
        span.set_attribute("payment.provider", provider)
        span.set_attribute("payment.amount", amount)

        # Simulate gateway latency
        delay = random.uniform(0.05, 0.15)
        is_slow = random.random() < SLOW_RATE

        if is_slow:
            delay = random.uniform(0.5, 2.0)
            span.set_attribute("payment.slow", True)
            logger.warning("Slow payment gateway response",
                            extra={"order_id": order_id, "provider": provider,
                                   "delay_ms": int(delay * 1000)})

        time.sleep(delay)

        # Record gateway duration metric
        gateway_duration.record(delay, {"provider": provider})
        span.set_attribute("payment.gateway_duration_ms", int(delay * 1000))

        # Simulate payment failure (10% chance)
        if random.random() < FAILURE_RATE:
            span.set_attribute("error", True)
            span.set_attribute("error.message", "Payment gateway timeout")

            payments_counter.add(1, {"status": "failed", "provider": provider})
            payment_amount.record(amount, {"status": "failed", "provider": provider})

            logger.error("Payment failed",
                          extra={"order_id": order_id, "provider": provider,
                                 "amount": amount, "error": "gateway_timeout"})

            return problem_response(
                500, "Payment Gateway Error",
                f"Payment gateway ({provider}) timed out for order {order_id}",
                instance="/charge",
                extra={"order_id": order_id, "provider": provider, "amount": amount},
            )

    # Success
    txn_id = f"txn-{random.randint(10000, 99999)}"

    payments_counter.add(1, {"status": "success", "provider": provider})
    payment_amount.record(amount, {"status": "success", "provider": provider})

    logger.info("Payment successful",
                 extra={"order_id": order_id, "provider": provider,
                        "amount": amount, "transaction_id": txn_id})

    return jsonify({
        "status": "success",
        "order_id": order_id,
        "transaction_id": txn_id,
        "provider": provider,
        "amount": amount,
    })


if __name__ == "__main__":
    logger.info("Payment Service starting (dev mode)", extra={"port": 5002})
    logger.warning("Use gunicorn for production: gunicorn -w 4 -b 0.0.0.0:5002 app:app")
    app.run(host="0.0.0.0", port=5002)
