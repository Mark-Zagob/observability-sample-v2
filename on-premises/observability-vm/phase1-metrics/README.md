# Phase 1: Metrics Foundation

## Prerequisites

- Docker Engine ≥ 24.x
- Docker Compose ≥ 2.x

## Quick Start

```bash
# 1. Tạo external network (chỉ cần 1 lần)
docker network create observability

# 2. Khởi chạy
docker compose up -d

# 3. Kiểm tra
docker compose ps
```

## Endpoints

| Service        | URL                      | Ghi chú               |
| -------------- | ------------------------ | ---------------------- |
| Prometheus     | http://<VM_IP>:9090      | Query, Targets, Alerts |
| Grafana        | http://<VM_IP>:3000      | admin / admin123       |
| Node Exporter  | http://<VM_IP>:9100      | Raw metrics            |
| cAdvisor       | http://<VM_IP>:8080      | Container metrics UI   |

## Dashboards (tự động load)

Vào Grafana → **Dashboards → folder "Infrastructure"**:

| Dashboard                    | Nội dung                                  |
| ---------------------------- | ----------------------------------------- |
| Node Exporter - Host         | CPU, Memory, Disk, Network của VM         |
| Docker Containers Monitoring | CPU, Memory, Network per container        |
| Prometheus Self-Monitoring   | Targets health, scrape, TSDB storage      |

## Quản lý

```bash
# Reload Prometheus config (không cần restart)
curl -X POST http://localhost:9090/-/reload

# Xem logs
docker compose logs -f prometheus
docker compose logs -f grafana

# Dừng
docker compose down

# Dừng + xoá data
docker compose down -v
```

## Cấu trúc

```
phase1-metrics/
├── docker-compose.yml
├── prometheus/
│   ├── prometheus.yml          # Scrape config
│   └── alert_rules.yml         # Alert rules
└── grafana/
    ├── dashboards/             # Dashboard JSON (as code)
    │   ├── node-exporter.json
    │   ├── docker-containers.json
    │   └── prometheus-self.json
    └── provisioning/
        ├── dashboards/
        │   └── dashboards.yml  # Dashboard provider
        └── datasources/
            └── prometheus.yml  # Datasource config
```
