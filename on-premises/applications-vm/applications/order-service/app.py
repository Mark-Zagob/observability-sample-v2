"""
============================================================
Order Service — Phase 5 + Shared Refactor
============================================================
Xử lý đơn hàng với PostgreSQL persistence và Redis cache.

Features:
  - PostgreSQL: persist orders, query products (with connection pool)
  - Redis: cache-aside pattern cho product catalog (TTL 60s)
  - OTel auto-instrumentation: psycopg2 + redis → spans tự động
  - Custom metrics: connection pool, cache hit/miss, query duration
  - Kafka event publishing with trace context
  - Health checks: /health/live, /health/ready
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
from shared.otel_watchdog import start_otel_watchdog # add watchdog
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

# Auto-instrumentation BEFORE creating connections
Psycopg2Instrumentor().instrument()
RedisInstrumentor().instrument()

# ============================================================
# Custom Metrics
# ============================================================
orders_counter = meter.create_counter(
    name="orders_created_total",
    description="Total orders created",
    unit="1",
)

order_duration = meter.create_histogram(
    name="order_processing_duration_seconds",
    description="Order processing duration in seconds",
    unit="s",
)

db_query_duration = meter.create_histogram(
    name="db_query_duration_seconds",
    description="Database query duration in seconds",
    unit="s",
)

db_pool_wait = meter.create_histogram(
    name="db_pool_wait_duration_seconds",  # <-- THÊM CHỮ "duration" ĐỂ MATCH VIEW
    description="Time spent waiting to get a connection from the pool",
    unit="s",
)

db_pool_active = meter.create_up_down_counter(
    name="db_connection_pool_active",
    description="Active database connections in pool",
    unit="1",
)

DB_POOL_MAX = 10  # must match maxconn in DatabasePool init below
# ⚠️ Connection math: 1 task × 10 conn = OK. But 10 services × 10 conn = 100 → RDS db.t3.micro limit (~150).
#    Phase 4 MUST introduce RDS Proxy to solve Connection Exhaustion. See ROADMAP.md Phase 4.

def _pool_max_callback(options):
    yield Observation(DB_POOL_MAX)

meter.create_observable_gauge(
    name="db_connection_pool_max",
    description="Maximum database connections in pool",
    unit="1",
    callbacks=[_pool_max_callback],
)

cache_ops_counter = meter.create_counter(
    name="cache_operations_total",
    description="Cache operations (hit/miss/set/error)",
    unit="1",
)

cache_duration = meter.create_histogram(
    name="cache_operation_duration_seconds",
    description="Cache operation latency",
    unit="s",
)

kafka_produced_counter = meter.create_counter(
    name="kafka_messages_produced_total",
    description="Total Kafka messages produced",
    unit="1",
)

inventory_checks_counter = meter.create_counter(
    name="inventory_checks_total",
    description="Total inventory stock checks by result",
    unit="1",
)

# ============================================================
# Database + Cache (using shared helpers)
# ============================================================
def _build_database_url():
    """Build DATABASE_URL from DB_SECRET + DB_HOST/DB_PORT/DB_NAME, or env var.

    AWS ECS Fargate:
      - DB_SECRET  = JSON from RDS managed secret: {"username":"...", "password":"..."}
      - DB_HOST    = RDS endpoint hostname (from SSM)
      - DB_PORT    = RDS port (from SSM)
      - DB_NAME    = Database name (from SSM)

    On-premises/docker-compose:
      - DATABASE_URL = full connection string directly
    """
    db_secret = os.getenv("DB_SECRET")
    if db_secret:
        s = json.loads(db_secret)
        host = os.getenv("DB_HOST", s.get("host", "localhost"))
        port = os.getenv("DB_PORT", str(s.get("port", 5432)))
        dbname = os.getenv("DB_NAME", s.get("dbname", "orders"))
        return f"postgresql://{s['username']}:{s['password']}@{host}:{port}/{dbname}?sslmode=require"
    # secretlint-disable-next-line
    return os.getenv("DATABASE_URL", "postgresql://app:app_secret@postgres:5432/orders")

DATABASE_URL = _build_database_url()
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
ENABLE_REDIS = os.getenv("ENABLE_REDIS", "true").lower() == "true"
ENABLE_KAFKA = os.getenv("ENABLE_KAFKA", "true").lower() == "true"

db = DatabasePool(DATABASE_URL, minconn=2, maxconn=DB_POOL_MAX,
                  pool_active_counter=db_pool_active,
                  query_duration_histogram=db_query_duration,
                  pool_wait_histogram=db_pool_wait)  # <-- Thêm dòng này
cache = RedisCache(REDIS_URL, ttl=60, cache_ops_counter=cache_ops_counter,
                   cache_duration=cache_duration) if ENABLE_REDIS else None


# ============================================================
# Schema Management Architecture Note:
# ============================================================
# Schema creation, migrations & seed data are 100% decoupled from app code.
# DDL execution is managed exclusively by the Migration Plane 
# (Dedicated ECS Migration Task / init-app.sql).
# Application runtime user operates under DML-only privileges (Least Privilege).

# ============================================================
# Kafka Producer Setup
# ============================================================
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = "order.events"

kafka_producer = None


def get_kafka_producer():
    """Lazy init Kafka producer with retry. Returns None if ENABLE_KAFKA=false."""
    if not ENABLE_KAFKA:
        return None
    global kafka_producer
    if kafka_producer is None:
        def _connect():
            producer = KafkaProducer({
                "bootstrap.servers": KAFKA_BOOTSTRAP,
                "client.id": "order-service",
                "acks": "all",
                "retries": 3,
                "retry.backoff.ms": 100,
                
                # 🌟 FIX BOMB #2: Natural Batching Configuration
                # Thay vì flush() sau mỗi request, để librdkafka tự batch:
                
                # linger.ms: Chờ tối đa 50ms để gom nhiều messages thành 1 batch
                # Trade-off: 50ms latency thêm vs giảm network calls đáng kể
                "linger.ms": 50,
                
                # batch.size: Kích thước batch tối đa (16KB)
                # Khi batch đầy hoặc linger.ms hết giờ → gửi đi
                "batch.size": 16384,
                
                # queue.buffering.max.messages: Buffer tối đa 100k messages
                # Nếu buffer đầy → produce() sẽ block hoặc throw exception
                # Đây là "Backpressure" mechanism của Kafka
                "queue.buffering.max.messages": 100000,
                
                # compression.type: Nén batch để giảm network bandwidth
                "compression.type": "lz4",
            })
            producer.list_topics(timeout=5)
            return producer
        logger.info("Initializing Kafka producer", extra={"bootstrap": KAFKA_BOOTSTRAP})
        kafka_producer = retry_connect("Kafka", _connect)
    return kafka_producer


def make_kafka_delivery_callback(event_type):
    """Factory returning a delivery callback with event_type in scope.
    
    Confluent Kafka callback signature is (err, msg). We use a closure
    to capture event_type from the publish_event call site, since the
    Message object doesn't expose custom metadata.
    """
    def _callback(err, msg):
        labels = {"status": "failed" if err else "success", "topic": msg.topic(), "event_type": event_type}
        kafka_produced_counter.add(1, labels)
        if err:
            logger.error("Kafka delivery failed",
                         extra={"topic": msg.topic(), "event_type": event_type, "error": str(err)})
        else:
            logger.info("Kafka message delivered",
                        extra={"topic": msg.topic(), "event_type": event_type,
                               "partition": msg.partition(), "offset": msg.offset()})
    return _callback


def publish_event(event_type, order_id, data):
    """Publish event to Kafka with trace context propagation"""
    event = {
        "event_type": event_type,
        "event_id": str(uuid.uuid4()),
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "order_id": order_id,
        "data": data,
    }

    # Inject trace context into Kafka headers
    headers = {}
    inject(headers)
    kafka_headers = [(k, v.encode("utf-8") if isinstance(v, str) else v)
                     for k, v in headers.items()]

    with tracer.start_as_current_span("kafka.produce") as span:
        span.set_attribute("messaging.system", "kafka")
        span.set_attribute("messaging.destination", KAFKA_TOPIC)
        span.set_attribute("messaging.operation", "publish")
        span.set_attribute("event.type", event_type)
        span.set_attribute("order.id", order_id)

        try:
            producer = get_kafka_producer()
            if producer is None:
                logger.debug("Kafka disabled, skipping event",
                             extra={"event_type": event_type, "order_id": order_id})
                return
            producer.produce(
                topic=KAFKA_TOPIC,
                key=order_id.encode("utf-8"),
                value=json.dumps(event).encode("utf-8"),
                headers=kafka_headers,
                callback=make_kafka_delivery_callback(event_type),
            )
            producer.poll(0)
            logger.info("Event published to Kafka",
                        extra={"event_type": event_type, "order_id": order_id,
                               "topic": KAFKA_TOPIC})
        except Exception as e:
            span.set_attribute("error", True)
            logger.error("Failed to publish Kafka event",
                         extra={"event_type": event_type, "order_id": order_id,
                                "error": str(e)})

# ────────────────────────────────────────────────────────────
# Graceful Shutdown Registration (Fix BOMB #2)
# ────────────────────────────────────────────────────────────
def flush_kafka_on_shutdown():
    """
    Flush toàn bộ Kafka buffer khi process chuẩn bị tắt.
    
    Timeout = 10s:
    - Đủ thời gian để gửi hết messages đang buffer
    - Nhỏ hơn ECS stopTimeout (60s) để tránh bị SIGKILL
    - Nếu flush timeout → log warning nhưng vẫn exit (fail-safe)
    """
    global kafka_producer
    if kafka_producer:
        logger.info("Flushing Kafka producer before exit (timeout=10s)...")
        try:
            # flush() sẽ block cho đến khi tất cả messages được gửi đi
            # hoặc timeout (10s)
            kafka_producer.flush(timeout=10)
            logger.info("Kafka producer flushed successfully")
        except Exception as e:
            logger.error(f"Failed to flush Kafka producer: {e}")
            # Không raise — vẫn exit process (fail-safe)

# Đăng ký callback với shutdown manager
shutdown_manager.register(
    callback=flush_kafka_on_shutdown,
    name="Kafka Producer",
    timeout_seconds=10
)

# 🆕 BOMB #3 FIX: Đóng PostgreSQL pool TRƯỚC KHI process exit
def close_db_pool_on_shutdown():
    """
    Đóng TẤT CẢ PostgreSQL connections khi ECS Fargate gửi SIGTERM.
    
    Tại sao PHẢI làm điều này?
    ─────────────────────────
    1. RDS db.t3.micro có max_connections ≈ 150 (hard limit)
    2. Order Service mở 10 connections/task (DB_POOL_MAX = 10)
    3. Khi Rolling Update, task cũ chết → connections trở thành "Ghost"
    4. Task mới mở 10 connections mới → Ghost vẫn chiếm slots
    5. Sau ~15 lần deploy → "FATAL: sorry, too many clients already"
    6. Toàn bộ Order Service down → Cascading Failure
    
    Cơ chế phòng vệ:
    ─────────────────
    - SIGTERM → shutdown_manager.exit_gracefully()
    - Gọi close_db_pool_on_shutdown() (timeout 5s)
    - psycopg2 pool.closeall() gửi TCP FIN cho tất cả connections
    - PostgreSQL nhận FIN → giải phóng backend process
    - Slots được trả về pool → Task mới có thể connect
    
    Order of cleanup:
    ─────────────────
    1. Kafka flush (10s) — push buffered messages
    2. PostgreSQL close (5s) — release connection slots
    3. Process exit (sys.exit(0))
    
    Total: ~15s, NHỎ HƠN ECS stopTimeout (60s) → An toàn
    """
    if db and hasattr(db, '_pool') and db._pool is not None:
        logger.info("Closing PostgreSQL connection pool before exit...")
        db.close_pool()

# Đăng ký callback với shutdown manager
shutdown_manager.register(
    callback=close_db_pool_on_shutdown,
    name="PostgreSQL Pool",
    timeout_seconds=5
)


def close_redis_on_shutdown():
    """
    Đóng Redis connections khi process tắt.
    
    Tại sao cần cho Order Service?
    ──────────────────────────────
    - Order Service dùng Redis làm cache cho product catalog
    - redis-py duy trì connection pool nội bộ
    - Nếu không close → ElastiCache giữ clients trong CLIENT LIST
    - Sau nhiều deploys → maxclients exhaustion
    
    Trade-off:
    ─────────
    - Cache-aside pattern: Redis down = cache miss, không phải outage
    - Nhưng connection leak = operational debt tích lũy
    """
    if cache is not None and hasattr(cache, '_client') and cache._client is not None:
        logger.info("Closing Redis connection pool before exit...")
        cache.close()

shutdown_manager.register(
    callback=close_redis_on_shutdown,
    name="Redis Cache",
    timeout_seconds=5
)
# ============================================================
# Flask App
# ============================================================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

PAYMENT_SERVICE = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:5002")

# --- Health checks ---
_health_checks = {"db": lambda: db.check_health()}
if cache is not None:
    _health_checks["cache"] = lambda: cache.check_health()
health_bp = create_health_blueprint("order-service", checks=_health_checks)
app.register_blueprint(health_bp)


@app.route("/products")
def list_products():
    """List product catalog (cache-aside pattern)"""
    with tracer.start_as_current_span("get_product_catalog") as span:
        # 1. Try cache first
        products = cache.get("product:catalog") if cache else None

        if products is not None:
            span.set_attribute("cache.hit", True)
            span.set_attribute("products.count", len(products))
            return jsonify({"products": products, "source": "cache"})

        # 2. Cache miss → query DB
        span.set_attribute("cache.hit", False)
        logger.info("Fetching products from database")

        rows = db.execute("SELECT id, name, price, stock, category FROM products ORDER BY id")
        products = [dict(row) for row in rows]

        # Convert Decimal to float for JSON
        for p in products:
            p["price"] = float(p["price"])

        # 3. Set cache
        if cache:
            cache.set("product:catalog", products)

        span.set_attribute("products.count", len(products))
        return jsonify({"products": products, "source": "database"})


@app.route("/orders")
def list_orders():
    """List recent orders"""
    with tracer.start_as_current_span("list_recent_orders") as span:
        limit = flask_request.args.get("limit", 20, type=int)
        rows = db.execute(
            "SELECT order_id, product_name, quantity, total_amount, status, "
            "payment_txn_id, created_at FROM orders ORDER BY created_at DESC LIMIT %s",
            (limit,)
        )
        orders = []
        for row in rows:
            o = dict(row)
            o["total_amount"] = float(o["total_amount"])
            o["created_at"] = o["created_at"].isoformat()
            orders.append(o)
        span.set_attribute("orders.count", len(orders))
        return jsonify({"orders": orders, "count": len(orders)})


@app.route("/process", methods=["GET", "POST"])
def process_order():
    """Xử lý đơn hàng — with real DB persistence"""
    start_time = time.time()
    order_id = str(uuid.uuid4())[:8]
    order_status = "completed"

    # Parse request body
    if flask_request.method == "POST" and flask_request.is_json:
        data = flask_request.get_json()
        product_id = data.get("product_id", random.randint(1, 5))
        quantity = data.get("quantity", random.randint(1, 3))
    else:
        product_id = random.randint(1, 5)
        quantity = random.randint(1, 3)

    logger.info("Processing new order",
                 extra={"order_id": order_id, "product_id": product_id, "quantity": quantity})

    # Step 1: Get product info (from cache or DB)
    with tracer.start_as_current_span("get_product_info") as span:
        span.set_attribute("product.id", product_id)

        product = None
        cached_catalog = cache.get("product:catalog") if cache else None
        if cached_catalog:
            for p in cached_catalog:
                if p["id"] == product_id:
                    product = p
                    break

        if product is None:
            rows = db.execute("SELECT id, name, price, stock FROM products WHERE id = %s",
                              (product_id,))
            if rows:
                product = dict(rows[0])
                product["price"] = float(product["price"])
            else:
                return problem_response(
                    404, "Product Not Found",
                    f"Product with id {product_id} does not exist",
                    instance="/process",
                    extra={"order_id": order_id},
                )

        span.set_attribute("product.name", product["name"])
        span.set_attribute("product.price", product["price"])

    # Step 2: Check inventory
    with tracer.start_as_current_span("check_inventory") as span:
        rows = db.execute("SELECT stock FROM products WHERE id = %s", (product_id,))

        # [FIX] Handle SQL NULL (Python None) safely - Fail-safe to 0
        raw_stock = rows[0]["stock"] if rows else None
        current_stock = raw_stock if raw_stock is not None else 0

        in_stock = current_stock >= quantity

        span.set_attribute("inventory.current_stock", current_stock)
        span.set_attribute("inventory.requested", quantity)
        span.set_attribute("inventory.in_stock", in_stock)

        check_result = "in_stock" if in_stock else "out_of_stock"
        inventory_checks_counter.add(1, {"result": check_result})

        logger.info("Inventory checked",
                     extra={"order_id": order_id, "product_id": product_id,
                            "stock": current_stock, "in_stock": in_stock})

        if not in_stock:
            order_status = "out_of_stock"
            orders_counter.add(1, {"status": order_status})

            # Publish stock.depleted event so inventory-worker can auto-restock
            publish_event("stock.depleted", order_id, {
                "product_id": product_id,
                "product_name": product["name"],
                "current_stock": current_stock,
                "quantity_requested": quantity,
            })

            return problem_response(
                409, "Out of Stock",
                f"Insufficient stock for {product['name']} (have {current_stock}, need {quantity})",
                instance="/process",
                extra={"order_id": order_id, "product_id": product_id,
                       "stock_available": current_stock, "quantity_requested": quantity},
            )

    total_amount = round(product["price"] * quantity, 2)

    # Step 3: Insert order into DB
    with tracer.start_as_current_span("insert_order") as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("order.total_amount", total_amount)

        db.execute(
            "INSERT INTO orders (order_id, product_id, product_name, quantity, total_amount, status) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (order_id, product_id, product["name"], quantity, total_amount, "pending"),
            fetch=False
        )
        logger.info("Order inserted into database",
                     extra={"order_id": order_id, "total_amount": total_amount})

    # Step 4: Update stock
    with tracer.start_as_current_span("update_stock") as span:
        db.execute(
            "UPDATE products SET stock = stock - %s WHERE id = %s AND stock >= %s",
            (quantity, product_id, quantity),
            fetch=False
        )
        span.set_attribute("stock.deducted", quantity)

        # Invalidate product cache since stock changed
        if cache:
            cache.delete("product:catalog")

    # Step 5: Process payment
    payment = {"status": "skipped"}
    with tracer.start_as_current_span("request_payment") as span:
        try:
            resp = requests.post(
                f"{PAYMENT_SERVICE}/charge",
                json={"order_id": order_id, "amount": total_amount},
                timeout=5,  # Timeout budget: caller (5s) < callee Gunicorn (30s). Validated by Exp 5.
            )
            payment = resp.json()
            payment_status = payment.get("status", "unknown")
            span.set_attribute("payment.status", payment_status)

            if resp.status_code != 200:
                order_status = "payment_failed"
            else:
                # Update order with payment info
                txn_id = payment.get("transaction_id", "")
                db.execute(
                    "UPDATE orders SET status = %s, payment_txn_id = %s, updated_at = NOW() "
                    "WHERE order_id = %s",
                    (order_status, txn_id, order_id),
                    fetch=False
                )

            logger.info("Payment processed",
                         extra={"order_id": order_id, "payment_status": payment_status})

        except Exception as e:
            span.set_attribute("error", True)
            order_status = "payment_error"
            payment = {"status": "failed", "error": str(e)}
            logger.error("Payment request failed",
                          extra={"order_id": order_id, "error": str(e)})

    # ── Publish Kafka events ──
    event_data = {
        "product_id": product_id,
        "product_name": product["name"],
        "quantity": quantity,
        "total_amount": total_amount,
    }

    publish_event("order.created", order_id, event_data)

    if order_status == "completed":
        event_data["payment_status"] = "success"
        event_data["transaction_id"] = payment.get("transaction_id", "")
        publish_event("order.payment_completed", order_id, event_data)
    elif order_status in ("payment_failed", "payment_error"):
        event_data["payment_status"] = "failed"
        event_data["error"] = payment.get("error", "unknown")
        publish_event("order.payment_failed", order_id, event_data)

    # Flush Kafka producer
    # ⚠️ Phase 2 TODO: Add signal.signal(SIGTERM, shutdown_handler) for graceful shutdown.
    #    ECS sends SIGTERM on scale-in/deploy → Flask doesn't catch it → Kafka messages may be lost.
    #    Acceptable risk for Phase 1 (no Kafka Workers yet). See ROADMAP.md Phase 2 Drill 3.
    # try:
    #     producer = get_kafka_producer()
    #     if producer:
    #         producer.flush(timeout=2)
    # except Exception:
    #     pass

    # Record metrics
    duration = time.time() - start_time
    orders_counter.add(1, {"status": order_status})
    order_duration.record(duration, {"status": order_status})

    logger.info("Order completed",
                 extra={"order_id": order_id, "status": order_status,
                        "duration_ms": int(duration * 1000),
                        "product": product["name"], "total_amount": total_amount})

    # [PLATFORM GUARDRAIL] Tự động map HTTP Code dựa trên Business Status
    http_status = map_order_status_to_http(order_status)

    # Giữ nguyên payload JSON để không break Contract với Web UI (Backward Compatible)
    # Nhưng thay đổi HTTP Envelope để API Gateway và Prometheus hiểu đúng bản chất
    return jsonify({
        "order_id": order_id,
        "product": product["name"],
        "quantity": quantity,
        "total_amount": total_amount,
        "payment": payment,
        "status": order_status,
    }), http_status


if __name__ == "__main__":
    logger.info("Order Service starting (dev mode)",
                 extra={"port": 5001, "db": DATABASE_URL.split("@")[1],
                        "redis_url": REDIS_URL})
    logger.warning("Use gunicorn for production: gunicorn -w 4 -b 0.0.0.0:5001 app:app")
    # Chỉ chạy watchdog khi app thực sự chạy (tránh chạy 2 lần do Flask reloader)
    start_otel_watchdog(interval=30, max_failures=3)
    app.run(host="0.0.0.0", port=5001)
