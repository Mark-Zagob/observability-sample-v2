# shared/otel_watchdog.py
import threading
import time
import urllib.request
import os
import logging

logger = logging.getLogger(__name__)

def start_otel_watchdog(interval=30, max_failures=3):
    """
    Background thread that checks ADOT sidecar health.
    If ADOT is dead for max_failures consecutive checks, kills the App container
    so ECS can restart the whole Task (App + Sidecar).
    """
    def watchdog_loop():
        failures = 0
        while True:
            time.sleep(interval)
            try:
                # Probe ADOT Health Extension endpoint
                req = urllib.request.urlopen('http://localhost:13133/', timeout=3)
                if req.status == 200:
                    failures = 0 # Reset nếu khỏe
            except Exception as e:
                failures += 1
                logger.warning(f"[Watchdog] ADOT sidecar health check failed ({failures}/{max_failures}): {e}")
                
                if failures >= max_failures:
                    logger.critical("[Watchdog] ADOT sidecar is permanently dead. Committing seppuku to force ECS Task restart.")
                    # os._exit(1) thoát ngay lập tức, bypass Python cleanup, 
                    # đảm bảo ECS Agent nhận diện container exit code 1 và restart Task.
                    os._exit(1)

    # Spawn daemon thread (thread này sẽ tự chết khi App process chính chết)
    thread = threading.Thread(target=watchdog_loop, daemon=True)
    thread.start()
    logger.info("[Watchdog] ADOT Sidecar Watchdog started.")