"""
============================================================
Idempotency Guard — Production-Grade Pattern
============================================================
Giải quyết BOMB #4: The Idempotency "Purgatory"

State Machine:
    none → processing (TTL 60s) → success (TTL 24h)
                                → failed (TTL 24h)
    
    Nếu process chết ở state "processing" → sau 60s key tự expire
    → User có thể retry lại.

Why Lua Script?
    - Atomic execution: Không có race condition giữa 2 requests đồng thời
    - Single round-trip: Giảm latency từ 3 Redis calls → 1 call
    - Server-side logic: Redis tự quyết định, client chỉ nhận kết quả

Usage:
    from shared.idempotency import IdempotencyGuard
    
    guard = IdempotencyGuard(redis_client)
    status = guard.acquire(order_id)
    
    if status == "blocked":
        # Request trùng lặp, trả về cached result
        return guard.get_cached_result(order_id)
    elif status == "acquired":
        # Lần đầu tiên, xử lý bình thường
        try:
            result = process_payment(order_id)
            guard.mark_success(order_id, result)
        except Exception as e:
            guard.mark_failed(order_id, str(e))
            raise
============================================================
"""
import json
import logging
import time
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


class IdempotencyGuard:
    """
    Production-grade idempotency guard với Redis Lua Script.
    
    Design decisions:
    - Split TTL: processing (60s) vs success (24h)
    - Atomic state transitions via Lua Script
    - Cached result storage để trả về nhanh cho duplicate requests
    - Stale detection để phát hiện zombie transactions
    """
    
    # 🌟 CRITICAL: Split TTL theo state
    PROCESSING_TTL = 60     # 60s cho "processing" state
    # Rationale: Bằng max timeout của Payment Gateway (5s) × 10 + buffer
    # Nếu process chết, sau 60s key tự expire → user retry được
    
    SUCCESS_TTL = 86400     # 24h cho "success" state
    # Rationale: Đủ dài để chống duplicate charge từ user retry
    
    FAILED_TTL = 3600       # 1h cho "failed" state
    # Rationale: Đủ dài để debug, nhưng không giữ quá lâu
    
    # Lua Script: Atomic state transition
    # Input: KEYS[1] = idempotency_key, ARGV[1] = ttl, ARGV[2] = value
    # Output: "acquired" | "blocked" | "stale"
    _ACQUIRE_SCRIPT = """
    local key = KEYS[1]
    local processing_ttl = tonumber(ARGV[1])
    local current = redis.call('GET', key)
    
    if current == false then
        -- Key chưa tồn tại → lần đầu tiên
        redis.call('SET', key, 'processing', 'EX', processing_ttl)
        return 'acquired'
    end
    
    -- Key đã tồn tại, kiểm tra state
    if current == 'processing' then
        -- Đang xử lý → check xem có phải zombie không
        local ttl = redis.call('TTL', key)
        if ttl < 0 then
            -- TTL bị mất (Redis bug hoặc manual delete) → reset
            redis.call('SET', key, 'processing', 'EX', processing_ttl)
            return 'acquired'
        end
        return 'blocked'
    end
    
    -- Key là "success" hoặc "failed" → duplicate request
    return 'blocked'
    """
    
    # Lua Script: Mark transaction as success
    # Input: KEYS[1] = idempotency_key, ARGV[1] = success_ttl, ARGV[2] = result_json
    _SUCCESS_SCRIPT = """
    local key = KEYS[1]
    local success_ttl = tonumber(ARGV[1])
    local result = ARGV[2]
    
    -- Chuyển state từ "processing" → "success:{result}"
    redis.call('SET', key, 'success:' .. result, 'EX', success_ttl)
    return 'ok'
    """
    
    # Lua Script: Mark transaction as failed
    _FAILED_SCRIPT = """
    local key = KEYS[1]
    local failed_ttl = tonumber(ARGV[1])
    local error_msg = ARGV[2]
    
    -- Chuyển state từ "processing" → "failed:{error}"
    redis.call('SET', key, 'failed:' .. error_msg, 'EX', failed_ttl)
    return 'ok'
    """
    
    def __init__(self, redis_client, prefix="idempotency:payment"):
        """
        Args:
            redis_client: Redis client instance
            prefix: Prefix cho Redis keys (để isolate giữa services)
        """
        self.redis = redis_client
        self.prefix = prefix
        
        # Register Lua scripts với Redis
        # SHA caching: Redis cache script, không phải parse lại mỗi lần gọi
        self._acquire_sha = self.redis.script_load(self._ACQUIRE_SCRIPT)
        self._success_sha = self.redis.script_load(self._SUCCESS_SCRIPT)
        self._failed_sha = self.redis.script_load(self._FAILED_SCRIPT)
        
        logger.debug("IdempotencyGuard initialized with Lua scripts")
    
    def _make_key(self, order_id: str) -> str:
        """Tạo Redis key từ order_id."""
        return f"{self.prefix}:{order_id}"
    
    def acquire(self, order_id: str) -> str:
        """
        Cố gắng "giành quyền" xử lý transaction.
        
        Returns:
            "acquired": Lần đầu tiên, bạn được phép xử lý
            "blocked":  Duplicate request, KHÔNG được xử lý
            "stale":    (Rare) Zombie transaction detected, bạn được phép xử lý
        
        Raises:
            Exception: Nếu Redis unavailable
        """
        key = self._make_key(order_id)
        
        try:
            # Execute Lua script atomically
            result = self.redis.evalsha(
                self._acquire_sha,
                1,  # Number of keys
                key,
                self.PROCESSING_TTL
            )
            
            logger.info(
                "Idempotency check",
                extra={
                    "order_id": order_id,
                    "status": result,
                    "key": key
                }
            )
            
            return result
            
        except Exception as e:
            # 🛡️ Graceful Degradation: Redis down = disable idempotency
            logger.warning(
                f"Redis unavailable, disabling idempotency: {e}",
                extra={"order_id": order_id}
            )
            return "acquired"  # Cho phép xử lý, chấp nhận risk duplicate
    
    def mark_success(self, order_id: str, result: Dict[str, Any]) -> None:
        """
        Đánh dấu transaction đã HOÀN TẤT thành công.
        
        Args:
            order_id: Order ID
            result: Dict chứa kết quả (txn_id, provider, amount...)
        """
        key = self._make_key(order_id)
        result_json = json.dumps(result, separators=(',', ':'))  # Compact JSON
        
        try:
            self.redis.evalsha(
                self._success_sha,
                1,
                key,
                self.SUCCESS_TTL,
                result_json
            )
            
            logger.info(
                "Transaction marked as success",
                extra={"order_id": order_id, "key": key}
            )
            
        except Exception as e:
            # Không raise — transaction đã thành công, chỉ log warning
            logger.error(
                f"Failed to mark success in Redis: {e}",
                extra={"order_id": order_id}
            )
    
    def mark_failed(self, order_id: str, error: str) -> None:
        """
        Đánh dấu transaction đã THẤT BẠI.
        
        Args:
            order_id: Order ID
            error: Error message
        """
        key = self._make_key(order_id)
        
        # Truncate error message nếu quá dài (Redis value limit)
        error_truncated = error[:200] if len(error) > 200 else error
        
        try:
            self.redis.evalsha(
                self._failed_sha,
                1,
                key,
                self.FAILED_TTL,
                error_truncated
            )
            
            logger.info(
                "Transaction marked as failed",
                extra={"order_id": order_id, "key": key, "error": error_truncated}
            )
            
        except Exception as e:
            # Không raise — transaction đã fail, chỉ log warning
            logger.error(
                f"Failed to mark failure in Redis: {e}",
                extra={"order_id": order_id}
            )
    
    def get_cached_result(self, order_id: str) -> Optional[Dict[str, Any]]:
        """
        Lấy cached result từ duplicate request.
        
        Returns:
            Dict chứa kết quả nếu transaction đã success, None otherwise
        """
        key = self._make_key(order_id)
        
        try:
            value = self.redis.get(key)
            if value and value.startswith("success:"):
                result_json = value[8:]  # Remove "success:" prefix
                return json.loads(result_json)
            return None
            
        except Exception as e:
            logger.warning(
                f"Failed to get cached result: {e}",
                extra={"order_id": order_id}
            )
            return None
    
    def release(self, order_id: str) -> None:
        """
        Giải phóng transaction (dùng khi cần retry thủ công).
        
        WARNING: Chỉ dùng trong admin tools, KHÔNG dùng trong app logic.
        """
        key = self._make_key(order_id)
        
        try:
            self.redis.delete(key)
            logger.warning(
                "Transaction released manually",
                extra={"order_id": order_id, "key": key}
            )
        except Exception as e:
            logger.error(
                f"Failed to release transaction: {e}",
                extra={"order_id": order_id}
            )