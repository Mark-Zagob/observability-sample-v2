import os

# --- Workers ---
# 2 workers × 8 threads = 16 concurrent requests (I/O bound workload)
workers = int(os.environ.get("GUNICORN_WORKERS", 2))
worker_class = "gthread"
threads = 8

# --- Timeouts ---
# Request timeout: Nếu 1 request treo > 30s → kill worker để giải phóng tài nguyên
timeout = 30
# Graceful timeout: Khi nhận SIGTERM, Gunicorn sẽ chờ tối đa 25s để worker xử lý xong request hiện tại
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
    init_profiling("api-gateway", "3.0.0")
    worker.log.info("✅ Pyroscope profiling initialized for worker %s", worker.pid)

def worker_int(worker):
    worker.log.info("🛑 Received SIGINT/SIGTERM, finishing current request gracefully...")

def on_exit(server):
    server.log.info("👋 API Gateway shut down cleanly.")
