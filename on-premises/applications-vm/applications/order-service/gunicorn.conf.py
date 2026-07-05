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

# --- Hooks: Bắt sự kiện SIGTERM để log (Rất quan trọng khi debug Chaos Drill) ---
def worker_int(worker):
    worker.log.info("🛑 Received SIGINT/SIGTERM, finishing current request gracefully...")

def on_exit(server):
    server.log.info("👋 Order Service shut down cleanly.")