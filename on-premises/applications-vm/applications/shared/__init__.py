# Shared utilities for microservices
#
# Only import modules that ALL services can use (no heavy deps).
# Services that need DB/Kafka should import directly:
#   from shared.db_utils import DatabasePool
#   from shared.kafka_utils import extract_trace_context
from shared.logging_config import setup_logging
from shared.otel_setup import init_otel
from shared.errors import problem_response
from shared.health import create_health_blueprint
