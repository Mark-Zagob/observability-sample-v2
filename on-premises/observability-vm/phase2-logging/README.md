# Phase 2: Logging (Loki + Alloy)

## Prerequisites

- Phase 1 đang chạy (Grafana cần restart để nhận datasource Loki)
- External network `observability` đã tạo

## Quick Start

```bash
# 1. Khởi chạy Loki + Alloy
cd /root/workspace/observability-lab/phase2-logging
docker compose up -d

# 2. Restart Grafana để load datasource Loki mới
cd /root/workspace/observability-lab/phase1-metrics
docker compose restart grafana

# 3. Kiểm tra
docker compose -f /root/workspace/observability-lab/phase2-logging/docker-compose.yml ps
```

## Endpoints

| Service | URL                  | Ghi chú                |
| ------- | -------------------- | ---------------------- |
| Loki    | http://<VM_IP>:3100  | API - check /ready     |
| Alloy   | http://<VM_IP>:12345 | Alloy UI (pipeline)    |

## Dashboard

Grafana → Dashboards → folder "Infrastructure" → **Docker Logs Overview**

## LogQL cheat sheet

```logql
# Tất cả logs từ 1 container
{container_name="prometheus"}

# Filter theo text
{container_name="grafana"} |= "error"

# Filter loại trừ
{compose_service="loki"} != "healthcheck"

# Regex filter
{container_name=~".*exporter.*"} |~ "(?i)warn|error"

# Đếm logs/phút theo container
sum by(container_name) (count_over_time({compose_project=~".+"}[1m]))

# Top 5 container nhiều error nhất
topk(5, sum by(container_name) (count_over_time({compose_project=~".+"} |= "error" [5m])))
```

## Cấu trúc

```
phase2-logging/
├── docker-compose.yml
├── loki/
│   └── loki-config.yml      # Storage, retention, schema
└── alloy/
    └── config.alloy          # Pipeline: discovery → collect → push

# Files thêm vào Phase 1:
phase1-metrics/grafana/
├── provisioning/datasources/
│   └── loki.yml              # Loki datasource (MỚI)
└── dashboards/
    └── docker-logs.json      # Log dashboard (MỚI)
```
