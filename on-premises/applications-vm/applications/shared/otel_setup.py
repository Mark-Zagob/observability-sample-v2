"""
OpenTelemetry setup — shared across all services.
Initializes tracing, metrics, and common auto-instrumentation.
"""
import os

from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.metrics.view import ExplicitBucketHistogramAggregation, View   # ← THÊM DÒNG NÀY
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

# ============================================================
# Histogram bucket boundaries cho duration metrics (seconds)
# ============================================================
# Default OTel SDK buckets: [0, 5, 10, 25, 50, 75, 100, 250, 500, ...]
# → Quá coarse khi unit="s" vì 400ms (0.4s) rơi vào bucket [0, 5]
# → histogram_quantile() nội suy tuyến tính → P95 ≈ 4.75s (SAI)
#
# Custom buckets bên dưới phù hợp cho latency measurement:
#   5ms → 10ms → 25ms → 50ms → 100ms → 250ms → 500ms → 1s → 2.5s → 5s → 10s
# ============================================================
DURATION_BUCKETS = [
    0.005,   # 5ms
    0.01,    # 10ms
    0.025,   # 25ms
    0.05,    # 50ms
    0.1,     # 100ms
    0.25,    # 250ms
    0.5,     # 500ms
    1.0,     # 1s
    2.5,     # 2.5s
    5.0,     # 5s
    10.0,    # 10s
]

# View áp dụng cho TẤT CẢ histogram metrics có tên kết thúc bằng "duration_seconds"
duration_view = View(
    instrument_name="*duration_seconds",
    aggregation=ExplicitBucketHistogramAggregation(boundaries=DURATION_BUCKETS),
)


def init_otel(service_name, service_version="1.0.0"):
    """Initialize OpenTelemetry tracing + metrics for a service.

    Args:
        service_name: Name for traces/metrics (e.g., "order-service")
        service_version: Service version string

    Returns:
        (tracer, meter) tuple
    """
    # 👇 FIX Q1: Parse endpoint an toàn cho cả gRPC và HTTP
    raw_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")
    
    # OTLP gRPC Exporter của Python KHÔNG chấp nhận prefix http:// hoặc https://
    # Nó chỉ chấp nhận format: "host:port"
    if raw_endpoint.startswith("http://"):
        endpoint = raw_endpoint.replace("http://", "")
    elif raw_endpoint.startswith("https://"):
        endpoint = raw_endpoint.replace("https://", "")
    else:
        endpoint = raw_endpoint

    resource = Resource.create({
        "service.name": service_name,
        "service.version": service_version,
        # 👇 Thêm Cloud Attribute để X-Ray / AMP nhận diện đây là task chạy trên ECS
        "cloud.platform": "aws_ecs_fargate" 
    })

    # --- Tracing ---
    trace_provider = TracerProvider(resource=resource)
    trace_provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True))
    )
    trace.set_tracer_provider(trace_provider)
    set_global_textmap(CompositePropagator([TraceContextTextMapPropagator()]))

    # --- Metrics ---
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=endpoint, insecure=True),
        export_interval_millis=10000,
    )
    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader],
        views=[duration_view],   # ← THÊM DÒNG NÀY: áp dụng custom histogram buckets
    )
    metrics.set_meter_provider(meter_provider)

    # --- Logging injection ---
    LoggingInstrumentor().instrument(set_logging_format=True)

    return trace.get_tracer(service_name), metrics.get_meter(service_name)
