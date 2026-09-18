import multiprocessing
import os

# --- Workers ---
workers = int(os.environ.get("GUNICORN_WORKERS", 4))
# [FIX] Chuyển từ "sync" sang "gthread" để không block worker khi sleep/I/O
worker_class = "gthread" 
threads = 4  # Mỗi worker có 4 threads -> Tổng cộng 4x4 = 16 concurrent requests

# --- Timeouts ---
# Timeout cho 1 request (nếu gateway treo quá 30s -> kill worker)
timeout = 30 
# Graceful timeout: Khi nhận SIGTERM, Gunicorn sẽ chờ tối đa 25s 
# để worker xử lý xong request hiện tại trước khi tắt hẳn.
# (Phải nhỏ hơn ECS stopTimeout 30s để tránh bị SIGKILL phập vào đầu)
graceful_timeout = 25 
keepalive = 5

# --- Logging ---
accesslog = "-"
errorlog = "-"
loglevel = "info"

# --- Hook: Bắt sự kiện SIGTERM ---
def worker_int(worker):
    worker.log.info("🛑 Received SIGINT/SIGTERM, finishing current request gracefully...")

def post_worker_init(worker):
    from shared.profiling_setup import init_profiling
    # Phase 4.5: Initialize Pyroscope profiling per-worker (fork-safe)
    init_profiling("payment-service", "2.0.0")
    worker.log.info("✅ Pyroscope profiling initialized for worker %s", worker.pid)

def on_exit(server):
    server.log.info("👋 Payment Service shut down cleanly.")