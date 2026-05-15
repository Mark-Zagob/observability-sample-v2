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
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator


def init_otel(service_name, service_version="1.0.0"):
    """Initialize OpenTelemetry tracing + metrics for a service.

    Args:
        service_name: Name for traces/metrics (e.g., "order-service")
        service_version: Service version string

    Returns:
        (tracer, meter) tuple
    """
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

    resource = Resource.create({
        "service.name": service_name,
        "service.version": service_version,
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
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)

    # --- Logging injection ---
    LoggingInstrumentor().instrument(set_logging_format=True)

    return trace.get_tracer(service_name), metrics.get_meter(service_name)
