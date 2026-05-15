"""
============================================================
API Gateway — Phase 5 + Shared Refactor
============================================================
API Gateway nhận HTTP requests, proxy tới backend services.

Endpoints:
  - POST /order       → create order (via order-service)
  - GET  /products    → list products (via order-service)
  - GET  /orders      → list orders (via order-service)
  - GET  /health      → readiness check (alias for /health/ready)
  - GET  /health/live → liveness check
  - GET  /health/ready → readiness check
============================================================
"""

import os
import time
import random
import requests
from flask import Flask, jsonify, request as flask_request

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
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# ----------------------------------------------------------
# Initialize logging + OTel
# ----------------------------------------------------------
logger = setup_logging("api-gateway")
tracer, meter = init_otel("api-gateway", "3.0.0")

# ============================================================
# Custom Metrics
# ============================================================
request_counter = meter.create_counter(
    name="api_gateway_requests_total",
    description="Total HTTP requests received by API Gateway",
    unit="1",
)

request_duration = meter.create_histogram(
    name="api_gateway_request_duration_seconds",
    description="HTTP request duration in seconds",
    unit="s",
)

# ============================================================
# Flask App
# ============================================================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://order-service:5001")

# --- Health checks ---
health_bp = create_health_blueprint("api-gateway", checks={
    "order-service": lambda: requests.get(
        f"{ORDER_SERVICE}/health/live", timeout=2
    ).raise_for_status(),
})
app.register_blueprint(health_bp)


@app.route("/")
def home():
    return jsonify({"service": "api-gateway", "status": "ok",
                    "endpoints": ["/order", "/products", "/orders", "/health"]})


@app.route("/order", methods=["GET", "POST"])
def create_order():
    """Tạo đơn hàng → gọi Order Service"""
    start_time = time.time()
    status = "success"

    with tracer.start_as_current_span("process_order_request") as span:
        # Parse request body for POST
        if flask_request.method == "POST" and flask_request.is_json:
            order_data = flask_request.get_json()
            product_id = order_data.get("product_id", random.randint(1, 5))
            quantity = order_data.get("quantity", random.randint(1, 3))
        else:
            product_id = random.randint(1, 5)
            quantity = random.randint(1, 3)

        span.set_attribute("order.product_id", product_id)
        span.set_attribute("order.quantity", quantity)
        span.set_attribute("http.user_agent",
                           flask_request.headers.get("User-Agent", "unknown"))

        # Validate input
        with tracer.start_as_current_span("validate_input") as val_span:
            time.sleep(random.uniform(0.005, 0.02))
            val_span.set_attribute("validation.product_id", product_id)
            val_span.set_attribute("validation.quantity", quantity)
            val_span.set_attribute("validation.passed", True)

        logger.info("Processing order request",
                     extra={"product_id": product_id, "quantity": quantity})

        # Call Order Service
        try:
            resp = requests.post(
                f"{ORDER_SERVICE}/process",
                json={"product_id": product_id, "quantity": quantity},
                timeout=5,
            )
            data = resp.json()
            order_id = data.get("order_id", "unknown")
            span.set_attribute("order.id", order_id)
            span.set_attribute("order.status", data.get("status", "unknown"))

            logger.info("Order created",
                         extra={"order_id": order_id, "product_id": product_id,
                                "status": data.get("status")})

            result = jsonify({"status": "success", "order": data})
            if resp.status_code != 200:
                # Forward RFC 7807 from downstream if present
                content_type = resp.headers.get("Content-Type", "")
                if "problem+json" in content_type:
                    return resp.content, resp.status_code, {"Content-Type": content_type}
                result = jsonify({
                    "status": "error",
                    "message": data.get("message", data.get("error", "Order failed")),
                    "order": data,
                }), resp.status_code
                status = "error"

        except requests.exceptions.Timeout:
            status = "error"
            span.set_attribute("error", True)
            span.set_attribute("error.message", "Order service timeout")
            logger.error("Order service timeout",
                          extra={"product_id": product_id, "timeout": 5})
            result = problem_response(
                504, "Gateway Timeout",
                "Order service did not respond within 5s",
                instance="/order",
            )

        except Exception as e:
            status = "error"
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            logger.error("Order creation failed",
                          extra={"error": str(e), "product_id": product_id})
            result = problem_response(
                502, "Bad Gateway",
                f"Order service unavailable: {e}",
                instance="/order",
            )

    # Record metrics
    duration = time.time() - start_time
    request_counter.add(1, {"endpoint": "/order", "status": status})
    request_duration.record(duration, {"endpoint": "/order", "status": status})

    return result


@app.route("/products")
def list_products():
    """Proxy to order-service /products"""
    start_time = time.time()
    status = "success"

    with tracer.start_as_current_span("proxy_list_products") as span:
        try:
            resp = requests.get(f"{ORDER_SERVICE}/products", timeout=5)
            result = resp.json()
            span.set_attribute("products.count",
                               len(result.get("products", [])))
            span.set_attribute("products.source", result.get("source", "unknown"))

            logger.info("Products fetched",
                         extra={"count": len(result.get("products", [])),
                                "source": result.get("source")})

        except Exception as e:
            status = "error"
            span.set_attribute("error", True)
            result = {"error": str(e)}
            logger.error("Failed to fetch products", extra={"error": str(e)})

    duration = time.time() - start_time
    request_counter.add(1, {"endpoint": "/products", "status": status})
    request_duration.record(duration, {"endpoint": "/products", "status": status})

    return jsonify(result)


@app.route("/orders")
def list_orders():
    """Proxy to order-service /orders"""
    start_time = time.time()
    status = "success"

    with tracer.start_as_current_span("proxy_list_orders") as span:
        try:
            limit = flask_request.args.get("limit", 20)
            resp = requests.get(f"{ORDER_SERVICE}/orders?limit={limit}", timeout=5)
            result = resp.json()
            span.set_attribute("orders.count", result.get("count", 0))

        except Exception as e:
            status = "error"
            span.set_attribute("error", True)
            result = {"error": str(e)}
            logger.error("Failed to fetch orders", extra={"error": str(e)})

    duration = time.time() - start_time
    request_counter.add(1, {"endpoint": "/orders", "status": status})
    request_duration.record(duration, {"endpoint": "/orders", "status": status})

    return jsonify(result)


if __name__ == "__main__":
    logger.info("API Gateway starting (dev mode)", extra={"port": 5000})
    logger.warning("Use gunicorn for production: gunicorn -w 4 -b 0.0.0.0:5000 app:app")
    app.run(host="0.0.0.0", port=5000)
