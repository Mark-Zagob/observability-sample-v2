"""
Database utilities — shared across services that use PostgreSQL/Redis.
"""
import time
import json
import logging

# psycopg2 and redis are imported lazily inside their respective classes
# so services that don't need them won't crash on import.

logger = logging.getLogger(__name__)

# ----------------------------------------------------------
# Connection resilience
# ----------------------------------------------------------
MAX_RETRIES = 5
RETRY_DELAY = 2  # seconds, doubles each retry


def retry_connect(name, connect_fn, max_retries=MAX_RETRIES, delay=RETRY_DELAY):
    """Retry a connection function with exponential backoff.

    Args:
        name: Human-readable name for logging
        connect_fn: Callable that returns the connection/client
        max_retries: Maximum number of retry attempts
        delay: Initial delay in seconds (doubles each retry)

    Returns:
        The connection object from connect_fn

    Raises:
        Last exception if all retries exhausted
    """
    last_error = None
    for attempt in range(1, max_retries + 1):
        try:
            result = connect_fn()
            logger.info(f"{name} connected", extra={"attempt": attempt})
            return result
        except Exception as e:
            last_error = e
            wait = delay * (2 ** (attempt - 1))
            logger.warning(f"{name} connection failed, retrying",
                           extra={"attempt": attempt, "max_retries": max_retries,
                                  "wait_seconds": wait, "error": str(e)})
            time.sleep(wait)
    logger.error(f"{name} connection failed after {max_retries} retries",
                 extra={"error": str(last_error)})
    raise last_error


def parse_db_url(url):
    """Parse postgresql://user:pass@host:port/dbname[?param=value...] into dict.

    Query-string params (VD sslmode=require) được tách ra và trả về như
    psycopg2 connection keywords. Nếu KHÔNG tách ở đây, phần
    "?sslmode=require" bị nuốt vào dbname → PostgreSQL báo lỗi
    'database "orders?sslmode=require" does not exist'.
    """
    url = url.replace("postgresql://", "")
    userpass, hostdb = url.split("@")
    # maxsplit=1: password từ AWS Secrets Manager thường chứa ":" (VD: "p@ss:w0rd!")
    user, password = userpass.split(":", 1)
    # maxsplit=1: dbname + query string tách riêng bên dưới
    hostport, path = hostdb.split("/", 1)
    host, port = hostport.split(":")

    # Tách query string (?sslmode=require&...) khỏi dbname
    extra_params = {}
    if "?" in path:
        dbname, query = path.split("?", 1)
        for pair in query.split("&"):
            if not pair:
                continue
            key, _, value = pair.partition("=")
            extra_params[key] = value
    else:
        dbname = path

    result = {
        "user": user, "password": password,
        "host": host, "port": int(port), "dbname": dbname,
    }
    # sslmode, connect_timeout, ... → truyền thẳng làm psycopg2 kwargs
    result.update(extra_params)
    return result


# ----------------------------------------------------------
# PostgreSQL helpers
# ----------------------------------------------------------
class DatabasePool:
    """Lazy-initialized PostgreSQL connection pool with metrics support."""

    def __init__(self, db_url, minconn=2, maxconn=10, pool_active_counter=None,
                 query_duration_histogram=None, pool_wait_histogram=None): # <-- Thêm param
        self._params = parse_db_url(db_url)
        # 🆕 BOMB #3 ENHANCEMENT: TCP Keep-Alive settings
        # Giúp PostgreSQL phát hiện "dead" connections nhanh hơn
        # Thay vì giữ idle connection 8 tiếng (mặc định), chỉ giữ 5 phút
        self._params['keepalives'] = 1              # Enable TCP keepalive
        self._params['keepalives_idle'] = 60        # 60s before first probe
        self._params['keepalives_interval'] = 15    # 15s between probes
        self._params['keepalives_count'] = 3        # 3 failed probes → close
        
        # 🆕 Connection timeout: Fail-fast nếu PostgreSQL không respond
        self._params['connect_timeout'] = 5         # 5s timeout khi connect
        
        # 🆕 Statement timeout: Prevent runaway queries
        # Nếu query chạy > 30s → PostgreSQL tự kill query (không phải connection)
        # Phòng vệ chống lại "Connection Thrashing" khi có slow query
        self._params['options'] = '-c statement_timeout=30000'  # 30s in ms
        self._minconn = minconn
        self._maxconn = maxconn
        self._pool = None
        self._pool_active_counter = pool_active_counter
        self._query_duration_histogram = query_duration_histogram
        self._pool_wait_histogram = pool_wait_histogram # <-- Gán vào self

    def _get_pool(self):
        if self._pool is None:
            import psycopg2.pool
            def _connect():
                return psycopg2.pool.ThreadedConnectionPool(
                    minconn=self._minconn, maxconn=self._maxconn, **self._params
                )
            self._pool = retry_connect("PostgreSQL", _connect)
        return self._pool

    def execute(self, query, params=None, fetch=True):
        """Execute a query, return rows (fetch=True) or rowcount (fetch=False)."""
        pool = self._get_pool()
        
        # --- BẮT ĐẦU ĐO THỜI GIAN CHỜ (QUEUE WAIT TIME) ---
        wait_start = time.time()
        conn = pool.getconn() # Nếu pool đầy (10/10), thread sẽ bị block (chờ) ở đây
        wait_duration = time.time() - wait_start
        
        if self._pool_wait_histogram:
            self._pool_wait_histogram.record(wait_duration, {"operation": "getconn"})
        # --- KẾT THÚC ĐO THỜI GIAN CHỜ ---

        if self._pool_active_counter:
            self._pool_active_counter.add(1)
        start = time.time()
        operation = query.strip().split()[0].upper() if query.strip() else "UNKNOWN"
        try:
            import psycopg2.extras
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(query, params)
                if fetch:
                    result = cur.fetchall()
                else:
                    conn.commit()
                    result = cur.rowcount
            return result
        except Exception as e:
            conn.rollback()
            logger.error("Database query failed",
                         extra={"query": query[:100], "error": str(e)})
            raise
        finally:
            duration = time.time() - start
            pool.putconn(conn)
            if self._pool_active_counter:
                self._pool_active_counter.add(-1)
            if self._query_duration_histogram:
                self._query_duration_histogram.record(duration, {"operation": operation})
            if duration > 0.1:
                logger.warning("Slow database query",
                               extra={"operation": operation,
                                      "duration_ms": round(duration * 1000, 1),
                                      "query": query[:200]})

    def get_conn(self):
        """Get a raw connection for manual transaction control."""
        return self._get_pool().getconn()

    def put_conn(self, conn):
        """Return a connection to the pool."""
        self._get_pool().putconn(conn)

    def check_health(self):
        """Check database connectivity. Returns True or raises."""
        self.execute("SELECT 1", fetch=True)
        return True

    def close_pool(self):
        """
        🛡️ BOMB #3 FIX: Đóng TẤT CẢ connections trong pool.
        
        Khi nào cần gọi?
        - Khi process nhận SIGTERM (trước khi exit)
        - Khi test teardown
        - Khi tái sử dụng pool object
        
        Tại sao phải gọi tường minh?
        - Python interpreter KHÔNG đảm bảo gọi __del__ khi exit
        - psycopg2 ThreadedConnectionPool KHÔNG auto-close khi process chết
        - Nếu không gọi, PostgreSQL giữ connections ở 'idle' state (Ghost Connections)
        - RDS max_connections sẽ bị exhaust sau vài lần Rolling Update
        
        Cơ chế:
        - closeall() gửi TCP FIN cho tất cả connections
        - PostgreSQL nhận ra client disconnect → giải phóng backend process
        - Slots trong max_connections được trả về pool
        """
        if self._pool is not None:
            try:
                self._pool.closeall()
                logger.info(
                    "PostgreSQL connection pool closed",
                    extra={
                        "minconn": self._minconn,
                        "maxconn": self._maxconn,
                        "closed_connections": self._maxconn  # Approximate
                    }
                )
            except Exception as e:
                # Không raise — fail-safe, process vẫn exit
                logger.error(
                    "Failed to close PostgreSQL pool",
                    extra={"error": str(e)}
                )
            finally:
                self._pool = None

# ----------------------------------------------------------
# Redis helpers
# ----------------------------------------------------------
class RedisCache:
    """Lazy-initialized Redis client with cache-aside pattern support."""

    def __init__(self, redis_url, ttl=60, cache_ops_counter=None, cache_duration=None):
        self._redis_url = redis_url
        self._ttl = ttl
        self._client = None
        self._cache_ops_counter = cache_ops_counter
        self._cache_duration = cache_duration

    def _get_client(self):
        if self._client is None:
            import redis as redis_lib
            def _connect():
                client = redis_lib.from_url(self._redis_url, decode_responses=True)
                client.ping()
                return client
            self._client = retry_connect("Redis", _connect)
        return self._client

    def get(self, key):
        """Get from cache. Returns parsed JSON or None."""
        start = time.time()
        try:
            value = self._get_client().get(key)
            duration = time.time() - start
            if self._cache_duration:
                self._cache_duration.record(duration, {"operation": "get"})

            if value is not None:
                if self._cache_ops_counter:
                    self._cache_ops_counter.add(1, {"operation": "get", "result": "hit"})
                return json.loads(value)
            else:
                if self._cache_ops_counter:
                    self._cache_ops_counter.add(1, {"operation": "get", "result": "miss"})
                return None
        except Exception as e:
            if self._cache_ops_counter:
                self._cache_ops_counter.add(1, {"operation": "get", "result": "error"})
            logger.error("Cache get failed", extra={"key": key, "error": str(e)})
            return None

    def set(self, key, value, ttl=None):
        """Set cache with TTL."""
        start = time.time()
        try:
            self._get_client().setex(key, ttl or self._ttl, json.dumps(value))
            duration = time.time() - start
            if self._cache_duration:
                self._cache_duration.record(duration, {"operation": "set"})
            if self._cache_ops_counter:
                self._cache_ops_counter.add(1, {"operation": "set", "result": "ok"})
        except Exception as e:
            if self._cache_ops_counter:
                self._cache_ops_counter.add(1, {"operation": "set", "result": "error"})
            logger.error("Cache set failed", extra={"key": key, "error": str(e)})

    def delete(self, key):
        """Delete a cache key."""
        try:
            self._get_client().delete(key)
            if self._cache_ops_counter:
                self._cache_ops_counter.add(1, {"operation": "delete", "result": "ok"})
        except Exception:
            pass

    def check_health(self):
        """Check Redis connectivity. Returns True or raises."""
        self._get_client().ping()
        return True

    def close(self):
        """
        🛡️ BOMB #3 FIX: Đóng Redis connection pool.
        
        Tại sao cần?
        - redis-py duy trì connection pool nội bộ (mặc định 2^31 connections)
        - Khi process exit, pool KHÔNG tự đóng → Redis giữ clients trong CLIENT LIST
        - Redis maxclients (mặc định 10000) sẽ bị exhaust sau nhiều deploys
        - ElastiCache có thể tính phí cho idle connections
        
        Cơ chế:
        - redis.close() đóng tất cả connections trong pool
        - Gửi QUIT command tới Redis server
        - Redis giải phóng client slot và file descriptors
        """
        if self._client is not None:
            try:
                self._client.close()
                logger.info("Redis connection pool closed")
            except Exception as e:
                logger.error(
                    "Failed to close Redis client",
                    extra={"error": str(e)}
                )
            finally:
                self._client = None