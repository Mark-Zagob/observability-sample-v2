"""
Standardized health check endpoints — liveness and readiness.

Usage:
    from shared.health import create_health_blueprint

    health_bp = create_health_blueprint("order-service", checks={
        "db": lambda: db.check_health(),
        "cache": lambda: cache.check_health(),
    })
    app.register_blueprint(health_bp)
"""
import time
from flask import Blueprint, jsonify


def create_health_blueprint(service_name, checks=None):
    """Create a Flask blueprint with /health/live and /health/ready endpoints.

    Args:
        service_name: Name of the service for response body
        checks: Dict of {name: callable} — each callable should return True
                or raise on failure. Used for readiness checks.

    Returns:
        Flask Blueprint with health endpoints
    """
    bp = Blueprint("health", __name__)
    _start_time = time.time()

    @bp.route("/health/live")
    def liveness():
        """Liveness: is the process running? Always 200 unless crashed."""
        return jsonify({
            "status": "up",
            "service": service_name,
        }), 200

    @bp.route("/health/ready")
    def readiness():
        """Readiness: can this service handle traffic?
        Checks all registered dependencies."""
        result = {
            "status": "ready",
            "service": service_name,
            "uptime_seconds": round(time.time() - _start_time, 1),
            "checks": {},
        }
        status_code = 200

        if checks:
            for name, check_fn in checks.items():
                try:
                    check_fn()
                    result["checks"][name] = "ok"
                except Exception as e:
                    result["checks"][name] = f"error: {str(e)}"
                    result["status"] = "not_ready"
                    status_code = 503

        return jsonify(result), status_code

    # Keep /health as alias for /health/ready (backward compatibility)
    @bp.route("/health")
    def health_alias():
        return readiness()

    return bp
