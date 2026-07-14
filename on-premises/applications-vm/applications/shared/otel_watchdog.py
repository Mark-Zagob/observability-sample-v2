import threading
import time
import urllib.request
import os
import logging

logger = logging.getLogger(__name__)

def start_otel_watchdog(interval=30, max_failures=3):
    """
    Background thread that checks ADOT sidecar health.
    Auto-disables itself if not running on AWS ECS.
    """
    # 🛡️ PLATFORM GUARDRAIL: Auto-detect AWS ECS environment
    # ECS Agent injects these URIs into every Fargate/EC2 task.
    is_ecs = "ECS_CONTAINER_METADATA_URI" in os.environ or "ECS_CONTAINER_METADATA_URI_V4" in os.environ
    
    if not is_ecs:
        logger.info("[Watchdog] Not running on AWS ECS. Watchdog disabled (On-Prem/Local mode).")
        return

    def watchdog_loop():
        failures = 0
        while True:
            time.sleep(interval)
            try:
                # Probe ADOT Health Extension endpoint (defined in otel-config-aws.yaml.tftpl)
                req = urllib.request.urlopen('http://localhost:13133/', timeout=3)
                if req.status == 200:
                    failures = 0
            except Exception as e:
                failures += 1
                logger.warning(f"[Watchdog] ADOT sidecar health check failed ({failures}/{max_failures}): {e}")
                
                if failures >= max_failures:
                    logger.critical("[Watchdog] ADOT sidecar is permanently dead. Committing seppuku to force ECS Task restart.")
                    # os._exit(1) bypass Python cleanup, ensures ECS Agent sees exit code 1 and restarts the whole Task.
                    os._exit(1)

    thread = threading.Thread(target=watchdog_loop, daemon=True, name="otel-watchdog")
    thread.start()
    logger.info("[Watchdog] ADOT Sidecar Watchdog started (ECS environment detected).")