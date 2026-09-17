"""
============================================================
Continuous Profiling Setup — Pyroscope SDK Integration
============================================================
Shared across all Python services to enable continuous profiling.

Features:
  - CPU profiling (hot functions, flame graphs)
  - Memory allocation profiling (memory leak detection)
  - GIL contention detection
  - Feature flag support (ENABLE_PROFILING env var)
  - Graceful degradation if Pyroscope is unavailable
  - Production guardrails (sampling rate control)

Usage:
    from shared.profiling_setup import init_profiling

    # In your app.py, AFTER init_otel()
    init_profiling("order-service")

Environment Variables:
    PYROSCOPE_URL          - Pyroscope server URL (default: http://pyroscope:4040)
    PYROSCOPE_SAMPLE_RATE  - Sampling frequency in Hz (default: 100)
    ENABLE_PROFILING       - Feature flag: true/false (default: true)
    ENABLE_MEMORY_PROFILING - Enable memory profiling (default: true)

Learning Value:
    - Understand flame graphs and hot path analysis
    - Detect CPU bottlenecks, memory leaks, GIL contention
    - Correlate profiling with traces and metrics (4th pillar)
    - Optimize code with data-driven decisions

Reference:
    - Official API: https://grafana.com/docs/pyroscope/latest/configure-client/language-sdks/python/
    - PyPI package: pyroscope-io
============================================================
"""

import os
import sys

# ============================================================
# Pyroscope SDK Import with Graceful Degradation
# ============================================================
# If Pyroscope SDK is not installed, profiling is disabled
# but the service continues to run normally.
#
# This is a production-grade pattern: observability should never
# block application startup or cause runtime errors.
#
# Note: The PyPI package name is `pyroscope-io` (not grafana-pyroscope).
# It provides the `pyroscope` module namespace [[1]].
# ============================================================
try:
    import pyroscope
    PYROSCOPE_AVAILABLE = True
except ImportError:
    PYROSCOPE_AVAILABLE = False


def init_profiling(service_name: str, service_version: str = "1.0.0"):
    """
    Initialize continuous profiling with Pyroscope SDK.

    Args:
        service_name: Name of the service (e.g., "order-service")
        service_version: Version string (e.g., "3.0.0")

    Returns:
        pyroscope module if profiling is enabled, None otherwise

    Example:
        >>> init_profiling("order-service", "3.0.0")
        <module 'pyroscope' from '...'>
    """
    # ============================================================
    # Feature Flag Check
    # ============================================================
    enable_profiling = os.getenv("ENABLE_PROFILING", "true").lower() == "true"

    if not enable_profiling:
        print(f"⏸️  Profiling disabled for {service_name} (ENABLE_PROFILING=false)")
        return None

    # ============================================================
    # SDK Availability Check
    # ============================================================
    if not PYROSCOPE_AVAILABLE:
        print(f"⚠️  Pyroscope SDK not installed. Profiling disabled.")
        print(f"   Install with: pip install pyroscope-io")
        return None

    # ============================================================
    # Configuration from Environment Variables
    # ============================================================
    pyroscope_url = os.getenv("PYROSCOPE_URL", "http://pyroscope:4040")
    sample_rate = int(os.getenv("PYROSCOPE_SAMPLE_RATE", "100"))
    enable_memory = os.getenv("ENABLE_MEMORY_PROFILING", "true").lower() == "true"

    # ============================================================
    # Initialize Pyroscope
    # ============================================================
    # Official API parameters [[1]]:
    #   application_name  - Service name (appears in Pyroscope UI)
    #                       NOTE: Must be `application_name`, NOT `app_name`
    #   server_address    - Pyroscope server endpoint
    #   sample_rate       - Sampling frequency (Hz). 100 = 100 samples/sec
    #                       Production: 100 Hz is typical (~1-2% CPU overhead)
    #   cpu_enabled       - Enable CPU profiling (default: True)
    #   mem_enabled       - Enable memory profiling (default: False)
    #                       Enable this to detect memory leaks!
    #   gil_only          - Only profile threads holding GIL (default: True)
    #                       Important for detecting GIL contention
    #   enable_logging    - Enable debug logging (default: False)
    #   tags              - Metadata tags for filtering/grouping
    #
    # Production Guardrails:
    #   - Sample rate 100 Hz = ~1-2% CPU overhead (acceptable)
    #   - Sample rate 1000 Hz = ~10% CPU overhead (too high for prod)
    #   - Start with 100 Hz, adjust based on overhead monitoring
    # ============================================================
    try:
        pyroscope.configure(
            application_name=service_name,
            server_address=pyroscope_url,
            sample_rate=sample_rate,
            # CPU profiling — always enabled
            cpu_enabled=True,
            # Memory profiling — detect memory leaks
            mem_enabled=enable_memory,
            # GIL contention detection — critical for multi-threaded Python
            gil_only=True,
            # Enable logging for debugging connection issues
            enable_logging=False,
            # Tags for filtering in Pyroscope UI
            tags={
                "environment": os.getenv("DEPLOYMENT_ENV", "lab"),
                "service": service_name,
                "version": service_version,
            }
        )
        print(f"✅ Profiling enabled for {service_name}")
        print(f"   Pyroscope URL: {pyroscope_url}")
        print(f"   Sample Rate: {sample_rate} Hz")
        print(f"   CPU Profiling: enabled")
        print(f"   Memory Profiling: {'enabled' if enable_memory else 'disabled'}")
        print(f"   GIL-only: True (detect GIL contention)")
        return pyroscope

    except Exception as e:
        # ============================================================
        # Graceful Degradation
        # ============================================================
        # If Pyroscope is unavailable (network error, server down),
        # log the error but continue running the service.
        #
        # This is critical: observability should never cause service
        # failures. Better to have no profiling than a crashed service.
        # ============================================================
        print(f"⚠️  Failed to initialize Pyroscope: {e}")
        print(f"   Service will continue without profiling.")
        return None


# ============================================================
# Utility Functions for Advanced Profiling
# ============================================================

def profile_function(pyroscope_instance, profile_name: str):
    """
    Decorator to profile a specific function with custom tags.

    Usage:
        profiler = init_profiling("my-service")

        @profile_function(profiler, "complex_calculation")
        def expensive_operation():
            # Your code here
            pass

    Args:
        pyroscope_instance: The pyroscope module returned by init_profiling()
        profile_name: Name for this profile (appears in flame graph)

    Returns:
        Decorator function
    """
    if pyroscope_instance is None:
        # If profiling is disabled, return a no-op decorator
        def noop_decorator(func):
            return func
        return noop_decorator

    def decorator(func):
        def wrapper(*args, **kwargs):
            with pyroscope_instance.tag_wrapper({"function": profile_name}):
                return func(*args, **kwargs)
        return wrapper
    return decorator


def tag_profiling_context(pyroscope_instance, **tags):
    """
    Add custom tags to profiling data for a code block.

    Usage:
        profiler = init_profiling("my-service")

        with tag_profiling_context(profiler, user_id="user-123", endpoint="/order"):
            # Code to profile with custom tags
            process_order()

    Args:
        pyroscope_instance: The pyroscope module returned by init_profiling()
        **tags: Key-value pairs to add as tags

    Returns:
        Context manager
    """
    if pyroscope_instance is None:
        # Return a no-op context manager if profiling is disabled
        from contextlib import nullcontext
        return nullcontext()

    return pyroscope_instance.tag_wrapper(tags)


# ============================================================
# Gunicorn Integration Helper
# ============================================================

def init_profiling_for_gunicorn():
    """
    Initialize profiling in gunicorn post_worker_init hook.

    This is the recommended approach for gunicorn because:
    1. gunicorn forks workers from master process
    2. Pyroscope starts background threads on configure()
    3. Background threads are NOT inherited after fork
    4. Must initialize AFTER fork, per-worker [[1]]

    Usage in gunicorn.conf.py:
        def post_worker_init(worker):
            from shared.profiling_setup import init_profiling_for_gunicorn
            init_profiling_for_gunicorn()
    """
    service_name = os.getenv("SERVICE_NAME", "unknown-service")
    service_version = os.getenv("SERVICE_VERSION", "1.0.0")
    return init_profiling(service_name, service_version)
