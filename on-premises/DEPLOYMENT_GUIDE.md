# 🚀 Deployment Guide — Linux VM

> Hướng dẫn deploy Reliability Lab trên Linux VM (Ubuntu 22.04/24.04 LTS recommended).
> Hỗ trợ 2 mô hình: **2 VMs** (production-like) và **1 VM** (lab đơn giản).

---

## 📋 Mục lục

1. [Prerequisites](#1-prerequisites)
2. [Chuẩn bị VM](#2-chuẩn-bị-vm)
3. [Clone & Setup Repository](#3-clone--setup-repository)
4. [Mô hình 2 VMs (Production-like)](#4-mô-hình-2-vms-production-like)
5. [Mô hình 1 VM (Lab đơn giản)](#5-mô-hình-1-vm-lab-đơn-giản)
6. [Verification](#6-verification)
7. [Troubleshooting](#7-troubleshooting)
8. [Cleanup & Reset](#8-cleanup--reset)

---

## 1. Prerequisites

### Hardware Requirements

| Mô hình | RAM | CPU | Disk | Network |
|---------|-----|-----|------|---------|
| **2 VMs** (Recommended) | App VM: 16GB, Obs VM: 8GB | App VM: 4 cores, Obs VM: 2 cores | 50GB each | 2 VMs cùng subnet |
| **1 VM** (Lab) | 16GB | 4 cores | 50GB | Single VM |

### Software Requirements

```bash
# Check OS version
lsb_release -a
# Expected: Ubuntu 22.04 LTS or 24.04 LTS

# Check Docker version (cần >= 24.0)
docker --version
# Expected: Docker version 24.x.x or higher

# Check Docker Compose version (cần >= 2.20)
docker compose version
# Expected: Docker Compose version v2.20.x or higher

# Check available disk space
df -h /
# Expected: At least 20GB free
```

---

## 2. Chuẩn bị VM

### 2.1 Install Docker (nếu chưa có)

```bash
# Remove old versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    tree \
    htop

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (avoid sudo)
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker run hello-world
docker compose version
```

### 2.2 Configure Docker Daemon (Production-grade)

```bash
# Create daemon.json with production settings
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "0.0.0.0:9323",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    }
  }
}
EOF

# Restart Docker to apply
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify daemon config
docker info | grep -E "Logging Driver|Storage Driver|Live Restore"
# Expected:
#   Logging Driver: json-file
#   Storage Driver: overlay2
#   Live Restore Enabled: true
```

### 2.3 Configure Logrotate cho Docker Host

```bash
# Create logrotate config for Docker
sudo tee /etc/logrotate.d/docker > /dev/null << 'EOF'
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 50M
}
EOF

# Test logrotate
sudo logrotate -d /etc/logrotate.d/docker
# Expected: no errors
```

### 2.4 Configure System Limits

```bash
# Increase file descriptor limits
sudo tee -a /etc/security/limits.conf > /dev/null << 'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

# Increase kernel limits
sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'
# Docker performance
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.max_map_count = 262144

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 524288
EOF

# Apply sysctl changes
sudo sysctl -p

# Verify
ulimit -n
# Expected: 65535
```

---

## 3. Clone & Setup Repository

```bash
# Create workspace directory
mkdir -p ~/workspaces
cd ~/workspaces

# Clone repository
git clone <your-repo-url> observability-sample-v2
cd observability-sample-v2/on-premises

# Verify structure
tree -L 2
# Expected: applications-vm/, observability-vm/, docs/...
```

### 3.1 Setup Environment Variables

```bash
# Create .env file for Telegram alerts (optional)
cat > .env << 'EOF'
# Telegram Bot Token for Alertmanager notifications
# Get from @BotFather on Telegram
TELEGRAM_BOT_TOKEN=your_bot_token_here

# Grafana credentials
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=***

# MinIO credentials
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=***
EOF

# Secure the .env file
chmod 600 .env
```

---

## 4. Mô hình 2 VMs (Production-like)

### Architecture

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│   Applications VM (100.57)       │     │   Observability VM (100.55)      │
│                                  │     │                                  │
│  ┌─────────────┐  ┌──────────┐  │     │  ┌──────────┐  ┌────────────┐  │
│  │ Applications │  │  Agents  │  │     │  │ Phase 1  │  │  Phase 2   │  │
│  │ (docker      │  │ (docker  │  │     │  │ Metrics  │  │  Logging   │  │
│  │  compose)    │  │  compose)│  │     │  │          │  │            │  │
│  └─────────────┘  └──────────┘  │     │  └──────────┘  └────────────┘  │
│         │               │        │     │         │              │        │
│         └───────────────┼────────┼─────┼─────────┼──────────────┘        │
│                         │  OTLP  │     │         │                       │
│                         └────────┼─────┘         │                       │
│                                  │               │                       │
│  ┌──────────┐  ┌──────────────┐  │     │  ┌──────┴───────┐  ┌────────┐ │
│  │ Postgres │  │ Kafka/Redis  │  │     │  │  Phase 3     │  │ Storage│ │
│  └──────────┘  └──────────────┘  │     │  │  Tracing     │  │ MinIO  │ │
│                                  │     │  └──────────────┘  └────────┘ │
└─────────────────────────────────┘     └─────────────────────────────────┘
```

### 4.1 Setup Observability VM (192.168.100.55)

```bash
# SSH vào Observability VM
ssh user@192.168.100.55

# Clone repository (same as above)
cd ~/workspaces/observability-sample-v2/on-premises

# Create the observability network (MUST be first)
docker network create observability

# Start Storage (MinIO) first
cd observability-vm/storage
docker compose up -d
docker compose ps  # Verify: minio healthy, minio-init exited 0

# Start Phase 1 (Metrics)
cd ../phase1-metrics
docker compose up -d
docker compose ps  # Verify: all services running

# Start Phase 2 (Logging)
cd ../phase2-logging
docker compose up -d
docker compose ps  # Verify: loki healthy, alloy running

# Start Phase 3 (Tracing)
cd ../phase3-tracing
docker compose up -d
docker compose ps  # Verify: tempo, otel-collector running

# Verify all services on Observability VM
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sort
```

**Expected Output (Observability VM):**
```
NAMES              STATUS                   PORTS
alertmanager       Up 2 minutes             0.0.0.0:9093->9093/tcp
blackbox-exporter  Up 2 minutes             0.0.0.0:9115->9115/tcp
cadvisor           Up 2 minutes             0.0.0.0:8080->8080/tcp
grafana            Up 2 minutes             0.0.0.0:3000->3000/tcp
loki               Up 2 minutes (healthy)   0.0.0.0:3100->3100/tcp
minio              Up 2 minutes (healthy)   0.0.0.0:9000-9001->9000-9001/tcp
node-exporter      Up 2 minutes             0.0.0.0:9100->9100/tcp
otel-collector     Up 2 minutes             0.0.0.0:4317-4318->4317-4318/tcp
prometheus         Up 2 minutes             0.0.0.0:9090->9090/tcp
tempo              Up 2 minutes             0.0.0.0:3200->3200/tcp
webhook-receiver   Up 2 minutes             0.0.0.0:9095->9095/tcp
```

### 4.2 Setup Applications VM (192.168.100.57)

```bash
# SSH vào Applications VM
ssh user@192.168.100.57

# Clone repository
cd ~/workspaces/observability-sample-v2/on-premises

# ⚠️ IMPORTANT: Update OTEL endpoint to point to Observability VM
# Check current config
grep "OTEL_EXPORTER_OTLP_ENDPOINT" applications-vm/applications/docker-compose.yml
# Should show: 192.168.100.55:4317

# If IPs are different, update:
sed -i 's/192.168.100.55/YOUR_OBSERVABILITY_VM_IP/g' applications-vm/applications/docker-compose.yml

# Start Agents first
cd applications-vm/agents
docker compose up -d
docker compose ps  # Verify: node-exporter, cadvisor, alloy running

# Start Applications
cd ../applications
docker compose up -d
docker compose ps  # Verify: all 12 services running

# Verify network segmentation
docker network ls
# Expected: frontend, backend, data, observability (4 networks)
```

### 4.3 Firewall Rules

```bash
# On Applications VM (192.168.100.57)
sudo ufw allow from 192.168.100.55 to any port 9100  # node-exporter
sudo ufw allow from 192.168.100.55 to any port 8080  # cadvisor
sudo ufw allow from 192.168.100.55 to any port 9308  # kafka-exporter
sudo ufw allow from 192.168.100.55 to any port 5000,5001,5002,5004,5005  # blackbox probes
sudo ufw allow 8580/tcp  # Web UI (external access)
sudo ufw allow 8585/tcp  # Kafka UI (dev only)
sudo ufw enable

# On Observability VM (192.168.100.55)
sudo ufw allow from 192.168.100.57 to any port 4317  # OTLP gRPC
sudo ufw allow from 192.168.100.57 to any port 4318  # OTLP HTTP
sudo ufw allow 3000/tcp  # Grafana (external access)
sudo ufw enable
```

---

## 5. Mô hình 1 VM (Lab đơn giản)

> Dùng khi không có 2 VMs. Tất cả chạy trên 1 VM duy nhất.

### 5.1 Update IP Addresses

```bash
cd ~/workspaces/observability-sample-v2/on-premises

# Replace Observability VM IP with localhost
# In applications compose
sed -i 's/192.168.100.55:4317/otel-collector:4317/g' \
    applications-vm/applications/docker-compose.yml

# In agents compose (Alloy config)
sed -i 's/192.168.100.55/loki/g' \
    applications-vm/agents/alloy/config.alloy

# In Prometheus config (remove remote targets, use local)
# This requires more changes - see section 5.2
```

### 5.2 Merge Docker Compose Files

Vì tất cả chạy trên 1 VM, cần merge tất cả compose files vào 1 file duy nhất để share networks.

```bash
# Create a merged compose file
cat > docker-compose-all.yml << 'COMPOSE_EOF'
# ============================================================
# All-in-One Docker Compose for Single VM Lab
# ============================================================
# Merge of:
#   - observability-vm/storage/docker-compose.yml
#   - observability-vm/phase1-metrics/docker-compose.yml
#   - observability-vm/phase2-logging/docker-compose.yml
#   - observability-vm/phase3-tracing/docker-compose.yml
#   - applications-vm/agents/docker-compose.yml
#   - applications-vm/applications/docker-compose.yml
# ============================================================
# Usage:
#   docker compose -f docker-compose-all.yml up -d
# ============================================================

# Common logging config
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "5"

x-app-hardening: &app-hardening
  read_only: true
  tmpfs:
    - /tmp
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true

services:
  # ==================== STORAGE ====================
  minio:
    image: minio/minio:RELEASE.2024-12-18T13-15-44Z
    container_name: minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: ***
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    networks:
      - observability
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    logging: *default-logging

  minio-init:
    image: minio/mc:RELEASE.2024-11-21T17-21-54Z
    container_name: minio-init
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
      mc alias set myminio http://minio:9000 minioadmin minioadmin;
      mc mb myminio/loki --ignore-existing;
      mc mb myminio/tempo --ignore-existing;
      mc anonymous set none myminio/loki;
      mc anonymous set none myminio/tempo;
      "
    networks:
      - observability
    restart: "no"
    logging: *default-logging

  # ==================== PHASE 3: TRACING ====================
  tempo:
    image: grafana/tempo:2.7.0
    container_name: tempo
    command: ["-config.file=/etc/tempo/tempo-config.yml"]
    volumes:
      - ./observability-vm/phase3-tracing/tempo/tempo-config.yml:/etc/tempo/tempo-config.yml:ro
      - tempo_data:/var/tempo
    ports:
      - "3200:3200"
    networks:
      - observability
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
    logging: *default-logging

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.120.0
    container_name: otel-collector
    command: ["--config=/etc/otel/otel-config.yml"]
    volumes:
      - ./observability-vm/phase3-tracing/otel-collector/otel-config.yml:/etc/otel/otel-config.yml:ro
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8889:8889"
      - "8890:8890"
    networks:
      - observability
      - backend    # Need to receive OTLP from app services
    depends_on:
      - tempo
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    logging: *default-logging

  # ==================== PHASE 2: LOGGING ====================
  loki:
    image: grafana/loki:3.3.2
    container_name: loki
    volumes:
      - ./observability-vm/phase2-logging/loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki_data:/loki
    command: -config.file=/etc/loki/loki-config.yml
    ports:
      - "3100:3100"
    networks:
      - observability
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
    logging: *default-logging

  # ==================== PHASE 1: METRICS ====================
  prometheus:
    image: prom/prometheus:v3.10.0
    container_name: prometheus
    volumes:
      - ./observability-vm/phase1-metrics/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./observability-vm/phase1-metrics/prometheus/alert_rules.yml:/etc/prometheus/alert_rules.yml:ro
      - ./observability-vm/phase1-metrics/prometheus/tracing_alert_rules.yml:/etc/prometheus/tracing_alert_rules.yml:ro
      - ./observability-vm/phase1-metrics/prometheus/recording_rules.yml:/etc/prometheus/recording_rules.yml:ro
      - ./observability-vm/phase1-metrics/prometheus/kafka_alert_rules.yml:/etc/prometheus/kafka_alert_rules.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
      - '--web.enable-remote-write-receiver'
      - '--enable-feature=exemplar-storage'
    ports:
      - "9090:9090"
    networks:
      - observability
      - backend    # Need to scrape app services
      - data       # Need to scrape kafka-exporter
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
    logging: *default-logging
    stop_grace_period: 30s

  grafana:
    image: grafana/grafana:12.3.3
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=***
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./observability-vm/phase1-metrics/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./observability-vm/phase1-metrics/grafana/dashboards:/var/lib/grafana/dashboards:ro
    ports:
      - "3000:3000"
    networks:
      - observability
    depends_on:
      - prometheus
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    logging: *default-logging

  alertmanager:
    image: prom/alertmanager:v0.28.1
    environment:
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
    container_name: alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    volumes:
      - ./observability-vm/phase1-metrics/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager_data:/alertmanager
    ports:
      - "9093:9093"
    networks:
      - observability
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging

  node-exporter-obs:
    image: prom/node-exporter:v1.10.2
    container_name: node-exporter-obs
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks:
      - observability
    restart: unless-stopped
    pid: host
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
    logging: *default-logging

  cadvisor-obs:
    image: gcr.io/cadvisor/cadvisor:v0.51.0
    container_name: cadvisor-obs
    privileged: true
    devices:
      - /dev/kmsg:/dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    networks:
      - observability
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging

  blackbox-exporter:
    image: prom/blackbox-exporter:v0.25.0
    container_name: blackbox-exporter
    volumes:
      - ./observability-vm/phase1-metrics/blackbox/blackbox.yml:/etc/blackbox_exporter/config.yml:ro
    ports:
      - "9115:9115"
    networks:
      - observability
      - backend    # Need to probe app services
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
    logging: *default-logging

  webhook-receiver:
    build: ./observability-vm/phase1-metrics/webhook-receiver
    container_name: webhook-receiver
    ports:
      - "9095:9095"
    networks:
      - observability
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
    logging: *default-logging

  # ==================== AGENTS ====================
  alloy:
    image: grafana/alloy:v1.13.2
    container_name: alloy
    user: root
    volumes:
      - ./applications-vm/agents/alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log/host:ro
    command:
      - run
      - /etc/alloy/config.alloy
      - --storage.path=/var/lib/alloy/data
      - --server.http.listen-addr=0.0.0.0:12345
    ports:
      - "12345:12345"
    networks:
      - observability
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    logging: *default-logging

  # ==================== APPLICATIONS ====================
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ***
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./applications-vm/applications/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d orders"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - data
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
    logging: *default-logging
    stop_grace_period: 60s

  redis:
    image: redis:7-alpine
    container_name: redis
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - data
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
    logging: *default-logging

  kafka:
    image: apache/kafka:3.7.0
    container_name: kafka
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_LOG_RETENTION_HOURS: 24
      KAFKA_JMX_PORT: 9101
      KAFKA_JMX_HOSTNAME: kafka
    ports:
      - "9092:9092"
    volumes:
      - kafka_data:/var/lib/kafka/data
    healthcheck:
      test: ["CMD-SHELL", "/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s
    networks:
      - data
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
    logging: *default-logging
    stop_grace_period: 60s

  kafka-exporter:
    image: danielqsj/kafka-exporter:latest
    container_name: kafka-exporter
    command:
      - "--kafka.server=kafka:9092"
      - "--topic.filter=.*"
      - "--group.filter=.*"
    ports:
      - "9308:9308"
    depends_on:
      kafka:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - data
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
    logging: *default-logging

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui
    environment:
      KAFKA_CLUSTERS_0_NAME: observability-lab
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
      DYNAMIC_CONFIG_ENABLED: "true"
    ports:
      - "8585:8080"
    depends_on:
      kafka:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - data
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
    logging: *default-logging

  api-gateway:
    build:
      context: ./applications-vm/applications
      dockerfile: api-gateway/Dockerfile
    container_name: api-gateway
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - ORDER_SERVICE_URL=http://order-service:5001
    ports:
      - "5000:5000"
    depends_on:
      - order-service
    <<: *app-hardening
    networks:
      - frontend
      - backend
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
    logging: *default-logging
    stop_grace_period: 30s

  order-service:
    build:
      context: ./applications-vm/applications
      dockerfile: order-service/Dockerfile
    container_name: order-service
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - PAYMENT_SERVICE_URL=http://payment-service:5002
      - DATABASE_URL=postgresql://app:app_secret@postgres:5432/orders
      - REDIS_URL=redis://redis:6379/0
      - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    ports:
      - "5001:5001"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      kafka:
        condition: service_healthy
    <<: *app-hardening
    networks:
      - backend
      - data
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
    logging: *default-logging
    stop_grace_period: 30s

  payment-service:
    build:
      context: ./applications-vm/applications
      dockerfile: payment-service/Dockerfile
    container_name: payment-service
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - REDIS_URL=redis://redis:6379/0
    ports:
      - "5002:5002"
    <<: *app-hardening
    networks:
      - backend
      - data
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging
    stop_grace_period: 30s

  notification-worker:
    build:
      context: ./applications-vm/applications
      dockerfile: notification-worker/Dockerfile
    container_name: notification-worker
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
      - DATABASE_URL=postgresql://app:***@postgres:5432/orders
      - KAFKA_SESSION_TIMEOUT=45000
      - KAFKA_ASSIGNMENT_STRATEGY=range
    ports:
      - "5004:5004"
    depends_on:
      kafka:
        condition: service_healthy
      postgres:
        condition: service_healthy
    restart: unless-stopped
    <<: *app-hardening
    networks:
      - backend
      - data
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging
    stop_grace_period: 30s

  inventory-worker:
    build:
      context: ./applications-vm/applications
      dockerfile: inventory-worker/Dockerfile
    container_name: inventory-worker
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
      - DATABASE_URL=postgresql://app:app_secret@postgres:5432/orders
    ports:
      - "5005:5005"
    depends_on:
      kafka:
        condition: service_healthy
      postgres:
        condition: service_healthy
    restart: unless-stopped
    <<: *app-hardening
    networks:
      - backend
      - data
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging
    stop_grace_period: 30s

  traffic-gen:
    build: ./applications-vm/applications/traffic-gen
    container_name: traffic-gen
    ports:
      - "5003:5003"
    depends_on:
      - api-gateway
    restart: unless-stopped
    <<: *app-hardening
    networks:
      - backend
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging: *default-logging

  web-ui:
    build: ./applications-vm/applications/web-ui
    container_name: web-ui
    ports:
      - "8580:8080"
    depends_on:
      - api-gateway
    restart: unless-stopped
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    networks:
      - frontend
      - backend
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
    logging: *default-logging

volumes:
  postgres_data:
  kafka_data:
  minio_data:
  prometheus_data:
  grafana_data:
  alertmanager_data:
  loki_data:
  tempo_data:

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
  data:
    driver: bridge
  observability:
    driver: bridge
COMPOSE_EOF
```

### 5.3 Deploy Single VM

```bash
# Start everything
docker compose -f docker-compose-all.yml up -d

# Wait for all services to start
sleep 60

# Check status
docker compose -f docker-compose-all.yml ps
```

---

## 6. Verification

### 6.1 Service Health Check

```bash
# Check all services are running
docker ps --format "table {{.Names}}\t{{.Status}}" | sort

# Check application health endpoints
for port in 5000 5001 5002 5004 5005; do
  echo "Port $port: $(curl -s http://localhost:$port/health/ready | jq -r .status)"
done
# Expected: all "ready"

# Check observability stack
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
# Expected: all targets "up"
```

### 6.2 Network Segmentation Verification

```bash
# ✅ web-ui CANNOT reach postgres (different networks)
docker exec web-ui ping -c 1 postgres 2>&1
# Expected: "bad address" or "Network is unreachable"

# ✅ api-gateway CAN reach order-service (same backend network)
docker exec api-gateway ping -c 1 order-service
# Expected: 1 packet received

# ✅ order-service CAN reach postgres (same data network)
docker exec order-service ping -c 1 postgres
# Expected: 1 packet received

# Verify network membership
docker inspect web-ui --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
# Expected: frontend backend
```

### 6.3 Resource Limits Verification

```bash
# Check resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Verify limits are applied
docker inspect api-gateway --format 'Memory: {{.HostConfig.Memory}}, CPUs: {{.HostConfig.NanoCpus}}'
# Expected: Memory: 536870912, CPUs: 1000000000
```

### 6.4 End-to-End Flow Test

```bash
# 1. Create an order
curl -X POST http://localhost:5000/order \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 1}' | jq .

# 2. Check Web UI
# Open browser: http://<VM_IP>:8580

# 3. Check Grafana dashboards
# Open browser: http://<VM_IP>:3000 (admin/admin123)

# 4. Check Kafka UI
# Open browser: http://<VM_IP>:8585

# 5. Check Prometheus targets
# Open browser: http://<VM_IP>:9090/targets
```

---

## 7. Troubleshooting

### Problem: Container cannot resolve DNS for other services

```bash
# Check if container is on the correct network
docker inspect <container_name> --format '{{json .NetworkSettings.Networks}}' | jq

# Restart the container
docker compose restart <service_name>

# Check Docker DNS
docker exec <container_name> nslookup <target_service>
```

### Problem: OTEL Collector cannot receive traces from apps

```bash
# Check OTEL endpoint in app environment
docker inspect api-gateway --format '{{.Config.Environment}}' | grep OTEL

# For 2 VMs: should be 192.168.100.55:4317
# For 1 VM: should be otel-collector:4317

# Check firewall
sudo ufw status
# Ensure port 4317 is open from App VM to Obs VM
```

### Problem: Prometheus targets are down

```bash
# Check Prometheus config
curl -s http://localhost:9090/api/v1/targets | jq

# For 2 VMs: remote targets should use App VM IP (192.168.100.57)
# For 1 VM: all targets should be local container names

# Check if target port is exposed
docker ps | grep <service_name>
```

### Problem: Kafka consumer lag growing

```bash
# Check Kafka UI: http://<VM_IP>:8585
# Check consumer groups
docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --all-groups

# Check worker logs
docker compose logs --tail=50 notification-worker
docker compose logs --tail=50 inventory-worker
```

---

## 8. Cleanup & Reset

### Stop all services

```bash
# For 2 VMs
# On Applications VM:
cd applications-vm/applications && docker compose down
cd ../agents && docker compose down

# On Observability VM:
cd observability-vm/phase3-tracing && docker compose down
cd ../phase2-logging && docker compose down
cd ../phase1-metrics && docker compose down
cd ../storage && docker compose down

# For 1 VM
docker compose -f docker-compose-all.yml down
```

### Remove volumes (CẢNH BÁO: mất data!)

```bash
# Remove all volumes
docker compose -f docker-compose-all.yml down -v

# Or selectively
docker volume rm observability-sample-v2_postgres_data
docker volume rm observability-sample-v2_kafka_data
```

### Remove networks

```bash
docker network rm frontend backend data observability
```

### Full reset

```bash
# Nuclear option: remove everything
docker compose -f docker-compose-all.yml down -v --rmi all --remove-orphans
docker system prune -af --volumes
```

---

## 📚 Quick Reference

### Port Summary

| Port | Service | Access |
|------|---------|--------|
| 3000 | Grafana | External |
| 5000 | API Gateway | External |
| 8080 | cAdvisor | Internal |
| 8580 | Web UI | External |
| 8585 | Kafka UI | External (dev) |
| 9090 | Prometheus | Internal |
| 9092 | Kafka | Internal |
| 9093 | Alertmanager | Internal |
| 9100 | Node Exporter | Internal |
| 9308 | Kafka Exporter | Internal |

### Useful Commands

```bash
# View logs
docker compose logs -f <service_name>

# Execute command in container
docker exec -it <container_name> sh

# Restart single service
docker compose restart <service_name>

# Scale service (for testing)
docker compose up -d --scale notification-worker=2

# Check resource usage
docker stats

# Check disk usage
docker system df
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-09-15  
**Next Review:** After deployment testing
