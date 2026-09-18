"""
Shared utilities for microservices.

Services should import specific modules explicitly:
    from shared.logging_config import setup_logging
    from shared.otel_setup import init_otel
    from shared.profiling_setup import init_profiling
"""
# NO EAGER IMPORTS — each module has its own dependencies
# Services only pay for the dependencies they actually use.