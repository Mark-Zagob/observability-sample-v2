"""
RFC 7807 Problem Details — standardized error responses.

See: https://datatracker.ietf.org/doc/html/rfc7807
"""
from flask import jsonify, make_response
from opentelemetry import trace


def problem_response(status, title, detail, instance=None, extra=None):
    """Create an RFC 7807 Problem Details response.

    Args:
        status: HTTP status code (e.g., 404, 409, 500)
        title: Short human-readable summary (e.g., "Out of Stock")
        detail: Detailed explanation (e.g., "Product 5 has 3 units, need 10")
        instance: URI reference for this specific occurrence (e.g., "/process")
        extra: Dict of additional fields to include in the response body

    Returns:
        Flask response with application/problem+json content type
    """
    body = {
        "type": "about:blank",
        "title": title,
        "status": status,
        "detail": detail,
    }

    if instance:
        body["instance"] = instance

    # Include trace_id for correlation with observability stack
    span = trace.get_current_span()
    span_context = span.get_span_context()
    if span_context and span_context.trace_id:
        body["trace_id"] = format(span_context.trace_id, "032x")

    if extra:
        body.update(extra)

    response = make_response(jsonify(body), status)
    response.content_type = "application/problem+json"
    return response

# ============================================================================
# Platform Contract: HTTP Semantic Mapping
# ============================================================================

def map_order_status_to_http(order_status: str) -> int:
    """
    [Platform Guardrail] Maps internal business order status to standard HTTP status codes.
    Prevents the 'HTTP 200 Trap' where business/infra failures incorrectly return 200 OK.
    
    - 200: Success
    - 402: Payment Required (Business failure, e.g., gateway rejected card)
    - 409: Conflict (Business state, e.g., out of stock)
    - 502: Bad Gateway (Dependency failure, e.g., payment service timeout)
    - 500: Internal Server Error (Catch-all for unknown/db/kafka errors)
    """
    mapping = {
        "completed": 200,
        "payment_failed": 402,
        "out_of_stock": 409,
        "payment_error": 502,
        "db_error": 500,
        "kafka_error": 500,
    }
    # Default to 500 for any unmapped critical errors to fail-safe
    return mapping.get(order_status, 500)