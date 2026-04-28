# ============================================================
# Observability Lab - Learning Roadmap
# ============================================================

### Phase 1: Metrics (Cơ bản) ✅
- [x] Prometheus + Node Exporter + cAdvisor + Grafana
- [x] Infrastructure dashboards (System, Docker, Prometheus)

### Phase 2: Logging (Cơ bản) ✅
- [x] Loki + Promtail + Grafana
- [x] Logging dashboards (Logs Explorer, Container Logs)

### Phase 3: Tracing (Trung cấp) ✅
- [x] Tempo + OTel Collector + Sample App (3 microservices)
- [x] Tracing dashboards (Overview, Service Map)
- [x] Tail-based sampling (keep errors 100%, slow 100%, random 10%)
- [x] SpanMetrics connector (auto RED metrics từ traces)

### Phase 4: Alerting (Trung cấp) ✅
- [x] Alertmanager setup (v0.28.1 + webhook-receiver)
- [x] Alert rules: infrastructure (Phase 1) + application/tracing (Phase 4)
- [x] Routing (severity-based), silencing, inhibition
- [x] Alerting Overview dashboard
- [x] Watchdog alert (Dead Man's Switch)
- [x] Recording rules (pre-computed metrics)
- [x] Telegram notifications
- [x] Predictive alerts (predict_linear)

### Phase 5: Application Instrumentation (Nâng cao) ✅
- [x] Custom metrics (Counter, Histogram) in app code
- [x] Structured JSON logging with trace_id injection
- [x] Enhanced span attributes
- [x] OTel Collector metrics pipeline
- [x] Prometheus scrape config for app metrics
- [x] Application Performance dashboard

### Phase 6: Correlation & SLO (Nâng cao) ✅
- [x] Loki derivedFields — Log → Trace correlation (click trace_id → Tempo)
- [x] Unified Overview dashboard (Metrics + Logs + Traces in one view)
- [x] SLI Recording Rules (availability, latency, payment success)
- [x] SLO Burn Rate Alerts (14x critical, 6x warning)
- [x] SLO Overview dashboard (gauges, trends, error budget)
