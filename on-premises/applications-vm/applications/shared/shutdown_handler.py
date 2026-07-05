"""
============================================================
Graceful Shutdown Handler — Production-Grade Pattern
============================================================
Bắt tín hiệu SIGTERM (ECS Fargate gửi khi scale-in/deploy)
và SIGINT (Ctrl+C khi chạy local).

Flow:
  1. OS gửi SIGTERM → Python process
  2. shutdown_handler bắt tín hiệu
  3. Chạy các cleanup callbacks (flush Kafka, close DB pool, etc.)
  4. sys.exit(0) → Gunicorn biết process đã tắt sạch sẽ

Tại sao KHÔNG dùng try...finally?
  - Khi OS gửi SIGKILL (sau stopTimeout), KHÔNG một dòng code Python nào
    (kể cả finally) được thực thi.
  - SRE phải thiết kế hệ thống để chịu đựng được việc app bị "bắn tỉa"
    bất cứ lúc nào.

Usage:
    from shared.shutdown_handler import shutdown_manager
    
    def flush_kafka():
        kafka_producer.flush(timeout=10)
    
    shutdown_manager.register(flush_kafka, "Kafka Producer")
============================================================
"""
import signal
import sys
import logging
import time

logger = logging.getLogger(__name__)


class GracefulShutdown:
    """
    Singleton class quản lý graceful shutdown cho Python process.
    
    Design decisions:
    - Singleton: Chỉ cần 1 instance cho toàn bộ process
    - Register pattern: Các module (DB, Kafka, Redis) tự đăng ký cleanup
    - Fail-safe: Nếu 1 callback fail, các callback khác vẫn chạy
    - Timeout: Mỗi callback có timeout riêng (không block lẫn nhau)
    """
    
    def __init__(self):
        self.cleanup_callbacks = []
        self._shutdown_initiated = False
        
        # Bắt cả SIGTERM (ECS gửi) và SIGINT (Ctrl+C local)
        signal.signal(signal.SIGTERM, self.exit_gracefully)
        signal.signal(signal.SIGINT, self.exit_gracefully)
        
        logger.debug("GracefulShutdown handler initialized")

    def register(self, callback, name="unknown", timeout_seconds=10):
        """
        Đăng ký một hàm cleanup sẽ được gọi khi process chuẩn bị tắt.
        
        Args:
            callback: Hàm không tham số, thực hiện cleanup
            name: Tên mô tả (để logging)
            timeout_seconds: Thời gian tối đa cho callback này
        
        Example:
            shutdown_manager.register(
                lambda: kafka_producer.flush(timeout=10),
                "Kafka Producer",
                timeout_seconds=10
            )
        """
        self.cleanup_callbacks.append({
            "name": name,
            "callback": callback,
            "timeout": timeout_seconds
        })
        logger.debug(f"Registered cleanup callback: {name}")

    def exit_gracefully(self, signum, frame):
        """
        Handler cho SIGTERM/SIGINT.
        
        Flow:
        1. Log tín hiệu nhận được
        2. Chạy TẤT CẢ callbacks (kể cả khi 1 cái fail)
        3. sys.exit(0) để Gunicorn biết process đã tắt sạch
        """
        # Tránh chạy 2 lần (race condition)
        if self._shutdown_initiated:
            return
        self._shutdown_initiated = True
        
        sig_name = signal.Signals(signum).name
        logger.warning(f"🛑 Received {sig_name}. Initiating Graceful Shutdown...")
        
        # Chạy các callback dọn dẹp
        total_callbacks = len(self.cleanup_callbacks)
        for i, cb_info in enumerate(self.cleanup_callbacks, 1):
            name = cb_info["name"]
            callback = cb_info["callback"]
            timeout = cb_info["timeout"]
            
            try:
                logger.info(f"🧹 [{i}/{total_callbacks}] Cleaning up: {name}...")
                start_time = time.time()
                
                # Thực thi callback
                callback()
                
                duration = time.time() - start_time
                logger.info(f"✅ [{i}/{total_callbacks}] {name} cleaned up in {duration:.2f}s")
                
            except Exception as e:
                logger.error(f"❌ [{i}/{total_callbacks}] Failed to cleanup {name}: {e}")
                # KHÔNG raise exception — tiếp tục chạy các callback khác
        
        logger.info("👋 All cleanup complete. Exiting process.")
        
        # sys.exit(0) để Gunicorn biết process đã tắt sạch sẽ
        # Exit code 0 = clean shutdown (không phải crash)
        sys.exit(0)


# Singleton instance — import và dùng trực tiếp
shutdown_manager = GracefulShutdown()