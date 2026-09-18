import os

# --- Workers ---
# 1 worker — Kafka consumer runs in a separate thread, Flask is just for health/status endpoints
workers = int(os.environ.get("GUNICORN_WORKERS", 1))
worker_class = "sync"

# --- Timeouts ---
timeout = 30
graceful_timeout = 25
keepalive = 5

# --- Logging ---
accesslog = "-"
errorlog = "-"
loglevel = "info"

# --- Hooks ---
def post_worker_init(worker):
    from shared.profiling_setup import init_profiling
    # Phase 4.5: Initialize Pyroscope profiling per-worker (fork-safe)
    init_profiling("notification-worker", "1.0.0")
    worker.log.info("✅ Pyroscope profiling initialized for worker %s", worker.pid)

def worker_int(worker):
    worker.log.info("🛑 Received SIGINT/SIGTERM, finishing current request gracefully...")

def on_exit(server):
    server.log.info("👋 Notification Worker shut down cleanly.")
