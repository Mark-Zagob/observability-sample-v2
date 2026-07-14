"""
Structured JSON logging setup — shared across all services.
"""
import logging
from pythonjsonlogger import json as json_logger


def setup_logging(name, level=logging.INFO):
    """Configure structured JSON logging for a service.

    Args:
        name: Logger name (e.g., "order-service")
        level: Logging level (default: INFO)

    Returns:
        Configured logger instance
    """
    handler = logging.StreamHandler()
    handler.setFormatter(json_logger.JsonFormatter(
        fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
        rename_fields={"asctime": "timestamp", "levelname": "level"},
    ))
    logging.basicConfig(level=level, handlers=[handler])
    return logging.getLogger(name)
