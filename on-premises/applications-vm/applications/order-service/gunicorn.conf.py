import multiprocessing
import os

# --- Workers ---
# Dùng 2 workers × 8 threads = 16 concurrent requests (I/O bound workload)
workers = int(os.environ.get("GUNICORN_WORKERS", 2))
worker_class = "gthread"  # Fix BOM #2: Không block worker khi sleep/I/O
threads = 8

# --- Timeouts ---
# Request timeout: Nếu 1 request treo > 30s → kill worker để giải phóng tài nguyên
timeout = 30

# 🌟 CRITICAL FIX BOMB #1: Graceful Shutdown Timeout
# Khi nhận SIGTERM, Gunicorn sẽ chờ tối đa 25s để worker xử lý xong request hiện tại.
# Con số này PHẢI NHỎ HƠN ECS stopTimeout (60s) để tránh bị SIGKILL "chặt đầu".
# Buffer 35s (60 - 25) dành cho: OS cleanup, network namespace teardown, ECS agent wrap-up.
graceful_timeout = 25

keepalive = 5

# --- Logging ---
accesslog = "-"
errorlog = "-"
loglevel = "info"

# --- Hooks ---

# 🔴 Finding 1 Fix: OTel Watchdog phải start PER WORKER.
# Dockerfile CMD chạy gunicorn → __name__ == "app" → if __name__ == "__main__"
# trong app.py KHÔNG chạy → watchdog inactive → silent telemetry loss.
# post_worker_init chạy SAU khi worker fork, đúng lifecycle.
def post_worker_init(worker):
    from shared.otel_watchdog import start_otel_watchdog
    start_otel_watchdog(interval=30, max_failures=3)
    worker.log.info("✅ OTel Watchdog started for worker %s", worker.pid)

# 🔴 Finding 2 Fix: Gunicorn Worker.init_signals() ghi đè SIGTERM.
# shutdown_manager.exit_gracefully() KHÔNG BAO GIỜ được gọi dưới gunicorn.
# → flush_kafka, close_db_pool, close_redis KHÔNG chạy.
# worker_exit chạy SAU khi gunicorn xử lý SIGTERM, TRƯỚC khi process exit.
def worker_exit(server, worker):
    from shared.shutdown_handler import shutdown_manager
    worker.log.info("🛑 Worker %s exiting, running cleanup callbacks...", worker.pid)
    shutdown_manager.run_cleanup()

def worker_int(worker):
    worker.log.info("🛑 Received SIGINT/SIGTERM, finishing current request gracefully...")

def on_exit(server):
    server.log.info("👋 Order Service shut down cleanly.")