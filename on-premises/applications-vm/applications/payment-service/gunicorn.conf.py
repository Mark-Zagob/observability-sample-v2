import multiprocessing
import os

# --- Workers ---
workers = int(os.environ.get("GUNICORN_WORKERS", 4))
worker_class = "sync"

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

def on_exit(server):
    server.log.info("👋 Payment Service shut down cleanly.")