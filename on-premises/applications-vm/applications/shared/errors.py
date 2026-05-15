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
