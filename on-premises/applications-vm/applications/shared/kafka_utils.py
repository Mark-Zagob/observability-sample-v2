"""
Kafka utilities — shared across services that produce/consume Kafka events.
"""
from opentelemetry.propagate import extract


def extract_trace_context(headers):
    """Extract OTel trace context from Kafka message headers.

    Args:
        headers: Kafka message headers (list of tuples)

    Returns:
        OTel context or None
    """
    if not headers:
        return None
    carrier = {}
    for key, value in headers:
        if isinstance(value, bytes):
            carrier[key] = value.decode("utf-8")
        else:
            carrier[key] = str(value)
    return extract(carrier)
