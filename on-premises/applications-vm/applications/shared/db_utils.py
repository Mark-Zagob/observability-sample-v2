"""
Database utilities — shared across services that use PostgreSQL/Redis.
"""
import time
import json
import logging

import psycopg2
import psycopg2.pool
import psycopg2.extras
import redis as redis_lib

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
    """Parse postgresql://user:pass@host:port/dbname into dict."""
    url = url.replace("postgresql://", "")
    userpass, hostdb = url.split("@")
    user, password = userpass.split(":")
    hostport, dbname = hostdb.split("/")
    host, port = hostport.split(":")
    return {
        "user": user, "password": password,
        "host": host, "port": int(port), "dbname": dbname,
    }


# ----------------------------------------------------------
# PostgreSQL helpers
# ----------------------------------------------------------
class DatabasePool:
    """Lazy-initialized PostgreSQL connection pool with metrics support."""

    def __init__(self, db_url, minconn=2, maxconn=10, pool_active_counter=None):
        self._params = parse_db_url(db_url)
        self._minconn = minconn
        self._maxconn = maxconn
        self._pool = None
        self._pool_active_counter = pool_active_counter

    def _get_pool(self):
        if self._pool is None:
            def _connect():
                return psycopg2.pool.ThreadedConnectionPool(
                    minconn=self._minconn, maxconn=self._maxconn, **self._params
                )
            self._pool = retry_connect("PostgreSQL", _connect)
        return self._pool

    def execute(self, query, params=None, fetch=True):
        """Execute a query, return rows (fetch=True) or rowcount (fetch=False)."""
        pool = self._get_pool()
        conn = pool.getconn()
        if self._pool_active_counter:
            self._pool_active_counter.add(1)
        try:
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
            pool.putconn(conn)
            if self._pool_active_counter:
                self._pool_active_counter.add(-1)

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
