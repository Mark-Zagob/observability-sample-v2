# Phase 3: Tracing (Tempo + OTEL + Sample App)

## Prerequisites

- Phase 1 + Phase 2 đang chạy
- External network `observability` đã tạo

## Quick Start

```bash
# 1. Chạy Phase 3
cd observability-lab/phase3-tracing
docker compose up -d --build

# 2. Restart Grafana để nhận Tempo datasource mới
cd ../phase1-metrics
docker compose restart grafana

# 3. Kiểm tra
docker compose -f ../phase3-tracing/docker-compose.yml ps
```

## Endpoints

| Service          | URL                 | Ghi chú                  |
| ---------------- | ------------------- | ------------------------ |
| Tempo            | http://<VM_IP>:3200 | Trace API                |
| OTEL Collector   | http://<VM_IP>:4317 | OTLP gRPC (apps gửi vào)|
| API Gateway      | http://<VM_IP>:5000 | Sample app entry point   |
| Order Service    | http://<VM_IP>:5001 | Internal service         |
| Payment Service  | http://<VM_IP>:5002 | Internal service         |

## Xem Traces

1. **Grafana → Explore → chọn datasource Tempo**
2. Chọn tab **Search** → click **Run query**
3. Click vào 1 trace → xem **waterfall timeline**

## Sample App Architecture

```
User → API Gateway → Order Service → Payment Service
         (5000)         (5001)           (5002)
```

Traffic Generator tự động gửi requests mỗi 2-5s.

## Cấu trúc

```
observability-lab/
├── sample-app/                  # ← Shared, top-level
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── api_gateway.py           # Service A
│   ├── order_service.py         # Service B
│   ├── payment_service.py       # Service C
│   └── traffic_gen.py           # Auto traffic
└── phase3-tracing/
    ├── docker-compose.yml
    ├── tempo/
    │   └── tempo-config.yml
    └── otel-collector/
        └── otel-config.yml
```
