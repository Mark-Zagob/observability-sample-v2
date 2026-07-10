"""
============================================================
Inventory Worker — Kafka Consumer + Shared Refactor
============================================================
Consume events từ topic 'order.events' và cập nhật stock.

Handles:
  - order.created → Reserve stock (giảm stock)
  - order.payment_failed → Release stock (hoàn stock)

Features:
  - Idempotency via processed_events table
  - Pessimistic locking (SELECT FOR UPDATE) for stock updates
  - Audit trail via inventory_log table
  - OTel trace context propagation from Kafka headers
  - Health checks: /health/live, /health/ready
============================================================
"""

import os
import time
import json
import signal
import threading
import atexit
import psycopg2.extras

# 🛡️ FIX: Import thêm KafkaException để xử lý lỗi khi manual commit fail
from confluent_kafka import Consumer, KafkaError, KafkaException
from flask import Flask, jsonify

# ----------------------------------------------------------
# Shared modules
# ----------------------------------------------------------
from shared.logging_config import setup_logging
from shared.otel_setup import init_otel
from shared.db_utils import DatabasePool
from shared.kafka_utils import extract_trace_context
from shared.health import create_health_blueprint

# ----------------------------------------------------------
# Auto-instrumentation imports
# ----------------------------------------------------------
from opentelemetry import context as otel_context
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor

# ----------------------------------------------------------
# Initialize logging + OTel
# ----------------------------------------------------------
logger = setup_logging("inventory-worker")
tracer, meter = init_otel("inventory-worker", "1.0.0")
Psycopg2Instrumentor().instrument()

# ============================================================
# Custom Metrics
# ============================================================
inventory_updates_counter = meter.create_counter(
    name="inventory_updates_total",
    description="Total inventory updates",
    unit="1",
)

inventory_processing_duration = meter.create_histogram(
    name="inventory_processing_duration_seconds",
    description="Inventory update processing duration",
    unit="s",
)

events_consumed_counter = meter.create_counter(
    name="kafka_events_consumed_total",
    description="Total Kafka events consumed",
    unit="1",
)

stock_update_errors = meter.create_counter(
    name="inventory_errors_total",
    description="Total inventory update errors",
    unit="1",
)

stock_restock_counter = meter.create_counter(
    name="inventory_restock_total",
    description="Total automatic restocks triggered",
    unit="1",
)

# ============================================================
# Config
# ============================================================
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "order.events")
KAFKA_GROUP = "inventory-workers"
# secretlint-disable-next-line
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://app:app_secret@postgres:5432/orders")

# Auto-restock config
RESTOCK_THRESHOLD = int(os.getenv("RESTOCK_THRESHOLD", "10"))
RESTOCK_AMOUNT = int(os.getenv("RESTOCK_AMOUNT", "100"))

# ============================================================
# Database (shared helper)
# ============================================================
db = DatabasePool(DATABASE_URL, minconn=2, maxconn=5)

def is_event_processed(event_id):
    """Check if event was already processed (idempotency)"""
    rows = db.execute(
        "SELECT 1 FROM processed_events WHERE event_id = %s AND processed_by = %s",
        (event_id, "inventory-worker")
    )
    return len(rows) > 0

def mark_event_processed(event_id, event_type):
    """Mark event as processed"""
    db.execute(
        "INSERT INTO processed_events (event_id, event_type, processed_by) VALUES (%s, %s, %s)",
        (event_id, event_type, "inventory-worker"),
        fetch=False
    )

# ============================================================
# Auto-Restock Logic
# ============================================================
def restock_product(product_id, current_stock):
    """Automatically restock a product when stock is low."""
    with tracer.start_as_current_span("auto_restock") as span:
        span.set_attribute("product.id", product_id)
        span.set_attribute("stock.current", current_stock)
        span.set_attribute("stock.restock_amount", RESTOCK_AMOUNT)
        
        conn = db.get_conn()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, name, stock FROM products WHERE id = %s FOR UPDATE",
                    (product_id,)
                )
                row = cur.fetchone()
                if not row:
                    conn.rollback()
                    return

                stock_before = row["stock"]

                # Only restock if still below threshold (avoid race conditions)
                if stock_before >= RESTOCK_THRESHOLD:
                    conn.rollback()
                    return

                stock_after = stock_before + RESTOCK_AMOUNT
                cur.execute(
                    "UPDATE products SET stock = %s WHERE id = %s",
                    (stock_after, product_id)
                )
                # Audit log with action='restock'
                cur.execute(
                    "INSERT INTO inventory_log "
                    "(event_id, order_id, product_id, action, quantity, stock_before, stock_after) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (f"restock-{product_id}-{int(time.time())}", "restock",
                     product_id, "restock", RESTOCK_AMOUNT, stock_before, stock_after)
                )
                conn.commit()

                stock_restock_counter.add(1, {"product_id": str(product_id)})
                span.set_attribute("stock.after", stock_after)

                logger.info("Auto-restock triggered",
                            extra={"product_id": product_id,
                                   "product_name": row["name"],
                                   "stock_before": stock_before,
                                   "stock_after": stock_after,
                                   "restock_amount": RESTOCK_AMOUNT})
        except Exception as e:
            conn.rollback()
            logger.error("Auto-restock failed",
                         extra={"product_id": product_id, "error": str(e)})
        finally:
            db.put_conn(conn)

# ============================================================
# Inventory Logic (uses raw connections for transaction control)
# ============================================================
def reserve_stock(event):
    """When order.created → decrease stock for the product"""
    order_id = event["order_id"]
    event_id = event["event_id"]
    data = event.get("data", {})
    product_id = data.get("product_id")
    quantity = data.get("quantity", 1)

    if not product_id:
        logger.warning("No product_id in event", extra={"order_id": order_id})
        return False

    conn = db.get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # Lock the row for update
            cur.execute(
                "SELECT id, stock FROM products WHERE id = %s FOR UPDATE",
                (product_id,)
            )
            row = cur.fetchone()
            if not row:
                logger.warning("Product not found", extra={"product_id": product_id})
                conn.rollback()
                return False

            stock_before = row["stock"]
            stock_after = max(0, stock_before - quantity)

            # Update stock
            cur.execute(
                "UPDATE products SET stock = %s WHERE id = %s",
                (stock_after, product_id)
            )
            # Write audit log
            cur.execute(
                "INSERT INTO inventory_log "
                "(event_id, order_id, product_id, action, quantity, stock_before, stock_after) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (event_id, order_id, product_id, "reserve", quantity, stock_before, stock_after)
            )
            conn.commit()

            logger.info("Stock reserved",
                        extra={"order_id": order_id, "product_id": product_id,
                               "quantity": quantity, "stock_before": stock_before,
                               "stock_after": stock_after})

            # Auto-restock when below threshold
            if stock_after < RESTOCK_THRESHOLD:
                restock_product(product_id, stock_after)

            return True
    except Exception as e:
        conn.rollback()
        logger.error("Failed to reserve stock",
                     extra={"error": str(e), "order_id": order_id,
                            "product_id": product_id})
        raise
    finally:
        db.put_conn(conn)

def release_stock(event):
    """When order.payment_failed → restore stock for the product"""
    order_id = event["order_id"]
    event_id = event["event_id"]
    data = event.get("data", {})
    product_id = data.get("product_id")
    quantity = data.get("quantity", 1)

    if not product_id:
        logger.warning("No product_id in event for release", extra={"order_id": order_id})
        return False

    conn = db.get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT id, stock FROM products WHERE id = %s FOR UPDATE",
                (product_id,)
            )
            row = cur.fetchone()
            if not row:
                logger.warning("Product not found for release",
                               extra={"product_id": product_id})
                conn.rollback()
                return False

            stock_before = row["stock"]
            stock_after = stock_before + quantity

            cur.execute(
                "UPDATE products SET stock = %s WHERE id = %s",
                (stock_after, product_id)
            )
            cur.execute(
                "INSERT INTO inventory_log "
                "(event_id, order_id, product_id, action, quantity, stock_before, stock_after) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (event_id, order_id, product_id, "release", quantity, stock_before, stock_after)
            )
            conn.commit()

            logger.info("Stock released",
                        extra={"order_id": order_id, "product_id": product_id,
                               "quantity": quantity, "stock_before": stock_before,
                               "stock_after": stock_after})

            return True
    except Exception as e:
        conn.rollback()
        logger.error("Failed to release stock",
                     extra={"error": str(e), "order_id": order_id,
                            "product_id": product_id})
        raise
    finally:
        db.put_conn(conn)

# ============================================================
# Kafka Consumer Loop
# ============================================================
consumer_running = True
consumer_stats = {"consumed": 0, "reserved": 0, "released": 0,
                  "skipped": 0, "ignored": 0, "errors": 0}
_start_time = time.time()

def consume_loop():
    """Main Kafka consumer loop"""
    global consumer_running

    logger.info("Starting Kafka consumer",
                extra={"bootstrap": KAFKA_BOOTSTRAP, "topic": KAFKA_TOPIC,
                       "group": KAFKA_GROUP})

    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": KAFKA_GROUP,
        "auto.offset.reset": "earliest",
        
        # 🛡️ FIX #1: TẮT AUTO-COMMIT ĐỂ TRÁNH MẤT DỮ LIỆU (THE SILENT DROP TRAP)
        "enable.auto.commit": False,  
        
        # ⚙️ Tối ưu cho Manual Commit & Rebalance
        "session.timeout.ms": int(os.getenv("KAFKA_SESSION_TIMEOUT", "45000")),
        "heartbeat.interval.ms": 10000, # Phải < 1/3 session.timeout.ms
        "max.poll.interval.ms": 300000, # 5 phút
        
        "partition.assignment.strategy": os.getenv("KAFKA_ASSIGNMENT_STRATEGY", "range") 
    })
    consumer.subscribe([KAFKA_TOPIC])

    try:
        while consumer_running:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                continue
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                logger.error("Kafka consumer error", extra={"error": str(msg.error())})
                continue

            start_time = time.time()

            try:
                # 1. Parse Message
                event = json.loads(msg.value().decode("utf-8"))
                event_id = event.get("event_id", "unknown")
                event_type = event.get("event_type", "unknown")
                order_id = event.get("order_id", "unknown")

                events_consumed_counter.add(1, {"event_type": event_type})
                consumer_stats["consumed"] += 1

                # Only handle stock-relevant events
                if event_type not in ("order.created", "order.payment_failed", "stock.depleted"):
                    consumer_stats["ignored"] += 1
                    # 🛡️ FIX: Vẫn commit offset để progress
                    try:
                        consumer.commit(asynchronous=False)
                    except KafkaException:
                        pass
                    continue

                # Extract trace context
                ctx = extract_trace_context(msg.headers())
                token = None
                if ctx:
                    token = otel_context.attach(ctx)

                try:
                    with tracer.start_as_current_span("kafka.consume") as span:
                        span.set_attribute("messaging.system", "kafka")
                        span.set_attribute("messaging.source", KAFKA_TOPIC)
                        span.set_attribute("messaging.operation", "process")
                        span.set_attribute("event.type", event_type)
                        span.set_attribute("order.id", order_id)
                        span.set_attribute("messaging.kafka.partition", msg.partition())
                        span.set_attribute("messaging.kafka.offset", msg.offset())

                        # Idempotency check
                        if is_event_processed(event_id):
                            span.set_attribute("event.duplicate", True)
                            logger.info("Duplicate event skipped",
                                        extra={"event_id": event_id, "event_type": event_type})
                            consumer_stats["skipped"] += 1
                            
                            # 🛡️ FIX: Vẫn phải commit offset nếu là duplicate
                            try:
                                consumer.commit(asynchronous=False)
                            except KafkaException:
                                pass
                            continue

                        # Process stock update
                        if event_type == "order.created":
                            with tracer.start_as_current_span("reserve_stock") as inv_span:
                                success = reserve_stock(event)
                                inv_span.set_attribute("inventory.action", "reserve")
                                inv_span.set_attribute("inventory.success", success)
                                if success:
                                    inventory_updates_counter.add(1, {
                                        "action": "reserve",
                                        "event_type": event_type,
                                    })
                                    consumer_stats["reserved"] += 1

                        elif event_type == "order.payment_failed":
                            with tracer.start_as_current_span("release_stock") as inv_span:
                                success = release_stock(event)
                                inv_span.set_attribute("inventory.action", "release")
                                inv_span.set_attribute("inventory.success", success)
                                if success:
                                    inventory_updates_counter.add(1, {
                                        "action": "release",
                                        "event_type": event_type,
                                    })
                                    consumer_stats["released"] += 1

                        elif event_type == "stock.depleted":
                            with tracer.start_as_current_span("handle_stock_depleted") as inv_span:
                                data = event.get("data", {})
                                product_id = data.get("product_id")
                                current_stock = data.get("current_stock", 0)

                                inv_span.set_attribute("inventory.action", "restock")
                                inv_span.set_attribute("product.id", str(product_id))

                                if product_id and current_stock < RESTOCK_THRESHOLD:
                                    restock_product(product_id, current_stock)
                                    inventory_updates_counter.add(1, {
                                        "action": "restock",
                                        "event_type": event_type,
                                    })

                        # Mark as processed
                        mark_event_processed(event_id, event_type)

                        # 🛡️ FIX #2: MANUAL COMMIT (SYNC) - THE CRITICAL STEP
                        try:
                            consumer.commit(asynchronous=False)
                        except KafkaException as commit_err:
                            logger.error(
                                "Failed to commit offset. Message will be re-processed.",
                                extra={"error": str(commit_err), "partition": msg.partition(), "offset": msg.offset()}
                            )

                        duration = time.time() - start_time
                        inventory_processing_duration.record(
                            duration, {"event_type": event_type})
                        span.set_attribute(
                            "processing.duration_ms", int(duration * 1000))

                finally:
                    if token:
                        otel_context.detach(token)

            except json.JSONDecodeError:
                # 🛡️ FIX #3: POISON PILL HANDLING
                logger.critical(
                    "Poison Pill detected: Invalid JSON. Committing offset to skip.",
                    extra={"partition": msg.partition(), "offset": msg.offset(), "raw_value": str(msg.value())[:100]}
                )
                try:
                    consumer.commit(asynchronous=False)
                except KafkaException:
                    logger.error("Failed to commit poison pill offset.")

            except Exception as e:
                consumer_stats["errors"] += 1
                stock_update_errors.add(1, {"event_type": event_type})
                logger.error("Failed to process Kafka message",
                             extra={"error": str(e), "partition": msg.partition(),
                                    "offset": msg.offset()})

    except KeyboardInterrupt:
        pass
    finally:
        # 🛡️ FIX #4: GRACEFUL SHUTDOWN COMMIT
        try:
            consumer.commit(asynchronous=False)
        except Exception:
            pass
        consumer.close()
        logger.info("Kafka consumer stopped", extra={"stats": consumer_stats})

# ============================================================
# Flask App (Health + Status)
# ============================================================
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

# --- Health checks ---
health_bp = create_health_blueprint("inventory-worker", checks={
    "db": lambda: db.check_health(),
})
app.register_blueprint(health_bp)

@app.route("/status")
def status():
    uptime = time.time() - _start_time
    return jsonify({
        "service": "inventory-worker",
        "status": "running" if consumer_running else "stopped",
        "consumer_group": KAFKA_GROUP,
        "topic": KAFKA_TOPIC,
        "events_processed": consumer_stats["reserved"] + consumer_stats["released"],
        "errors": consumer_stats["errors"],
        "uptime_seconds": round(uptime, 1),
        "stats": consumer_stats,
        "running": consumer_running,
    })

@app.route("/inventory")
def list_inventory():
    """List current product stock levels"""
    try:
        rows = db.execute(
            "SELECT id, name, price, stock, category FROM products ORDER BY id"
        )
        products = [dict(r) for r in rows]
        return jsonify({"products": products, "count": len(products)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/inventory/log")
def inventory_log():
    """List recent inventory changes"""
    limit = 30
    try:
        rows = db.execute(
            "SELECT event_id, order_id, product_id, action, quantity, "
            "stock_before, stock_after, created_at "
            "FROM inventory_log ORDER BY created_at DESC LIMIT %s",
            (limit,)
        )
        log = []
        for row in rows:
            entry = dict(row)
            entry["created_at"] = entry["created_at"].isoformat()
            # UI expects quantity_change (negative for reserve, positive for release)
            if entry["action"] == "reserve":
                entry["quantity_change"] = -entry.get("quantity", 0)
            else:
                entry["quantity_change"] = entry.get("quantity", 0)
            log.append(entry)
        return jsonify({"log": log, "count": len(log)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ============================================================
# Graceful Shutdown
# ============================================================
def _shutdown_handler(signum, frame):
    """Handle SIGTERM/SIGINT for graceful Kafka consumer shutdown."""
    global consumer_running
    sig_name = signal.Signals(signum).name
    logger.info(f"Received {sig_name}, shutting down gracefully...",
                extra={"signal": sig_name})
    consumer_running = False

signal.signal(signal.SIGTERM, _shutdown_handler)
signal.signal(signal.SIGINT, _shutdown_handler)
atexit.register(lambda: logger.info("Inventory Worker exiting",
                                     extra={"stats": consumer_stats}))

# ============================================================
# Start Kafka consumer thread
# ============================================================
_consumer_thread = threading.Thread(target=consume_loop, daemon=True, name="kafka-consumer")
_consumer_thread.start()
logger.info("Kafka consumer thread started", extra={"consumer_thread": _consumer_thread.name})

# ============================================================
# Main (dev mode only)
# ============================================================
if __name__ == "__main__":
    logger.info("Inventory Worker starting (dev mode)",
                extra={"port": 5005, "kafka": KAFKA_BOOTSTRAP, "topic": KAFKA_TOPIC})
    logger.warning("Use gunicorn for production: gunicorn -w 1 -b 0.0.0.0:5005 app:app")
    app.run(host="0.0.0.0", port=5005)