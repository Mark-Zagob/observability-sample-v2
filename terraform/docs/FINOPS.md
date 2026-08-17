# 💰 AWS FinOps — Cost Survival Guide

> **"The cloud is just someone else's computer — and someone else's electricity bill."**
>
> Tài liệu này giúp bạn **tránh bill shock**, hiểu rõ **hidden costs** của AWS, và tối ưu chi phí lab từ ~$300/tháng xuống còn ~$90/tháng (giảm 70%) mà vẫn giữ được production-grade learning experience.

🔗 **Cross-Reference:** [README.md](../README.md) | [TRADE_OFFS.md](TRADE_OFFS.md) | [AWS_TERRAFORM_PLAYBOOK.md](AWS_TERRAFORM_PLAYBOOK.md)

---

## 📊 Executive Summary

| Metric | Before Optimization | After Optimization | Savings |
|---|---|---|---|
| **Monthly cost (24/7)** | ~$300 | ~$150 | 50% |
| **Daily cost (lab hours only)** | $10/day | $3/day | 70% |
| **Hidden costs** | ~$80/month | ~$10/month | 87% |
| **Biggest killer** | MSK + NAT Gateway | Right-sized + scheduled | — |

### 🎯 3 Quick Wins (áp dụng ngay hôm nay)

1. **Destroy khi không dùng** → Tiết kiệm 60% bill
2. **Dùng single NAT Gateway** thay vì 3 NATs → Tiết kiệm $64/tháng
3. **Tắt MSK khi không lab Kafka** → Tiết kiệm $150/tháng

---

## 🗡️ Phần 1: The Hidden Killers — Những Chi Phí Ẩn

Đây là những chi phí **không hiện rõ** trong AWS Pricing Calculator nhưng chiếm **30–50% bill thực tế**.

### 🔪 Killer #1: Cross-AZ Data Transfer ($0.01/GB)

**Vấn đề:** Mỗi GB data đi qua AZ boundary = $0.01. Lab có 3 AZs → traffic giữa các services trong VPC **có thể** đi cross-AZ. Đặc biệt nguy hiểm với MSK Kafka (producer AZ-a → broker AZ-b → consumer AZ-c = 2 lần cross-AZ), ElastiCache Redis, và RDS read replica cross-AZ queries.

**Ví dụ thực tế:**

```
Order Service (AZ-a) → MSK Broker (AZ-b) → Inventory Worker (AZ-c)
= 100MB message × $0.01/GB × 2 hops = $0.002/message
10,000 messages/day = $20/day = $600/month 😱
```

**Mitigation:**

```hcl
# Module: network - AZ-aware placement
# Keep producer + broker + consumer in same AZ khi có thể
# Sử dụng "rack awareness" trong Kafka consumer config
```

**Cost impact:** $20–100/tháng nếu không optimize

---

### 🔪 Killer #2: NAT Gateway Processing ($0.045/GB)

**Vấn đề:** NAT Gateway charge $0.045/GB data processed (không chỉ hourly). Mọi outbound traffic từ private subnet đều qua NAT: pull Docker images từ ECR (~500MB/image), push logs lên CloudWatch, call AWS APIs (Secrets Manager, SSM, KMS), OTel Collector push metrics.

**Ví dụ thực tế:**

```
10 ECS tasks × pull image 500MB/day = 5GB/day
CloudWatch Logs: 1GB/day
OTel metrics: 500MB/day
Total: ~7GB/day × $0.045 = $9.45/month (just for NAT processing)
```

**Mitigation (VPC Endpoints):**

```hcl
# Module: vpc-endpoints
# Gateway Endpoints (FREE): S3, DynamoDB
# Interface Endpoints ($0.01/hr/AZ): ECR, SSM, Secrets Manager, STS, Logs

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  # Gateway endpoint = FREE data transfer
}
```

**Cost impact:** Không có endpoints: $30–50/tháng. Có endpoints: $7–15/tháng.

---

### 🔪 Killer #3: VPC Interface Endpoints Hourly ($0.01/hr/AZ)

**Vấn đề:** Mỗi Interface Endpoint = $0.01/hour/AZ. Lab có 3 AZs × 5 endpoints = $108/tháng 😱

```
5 endpoints × 3 AZs × 24 hours × 30 days × $0.01 = $108/month
```

**Mitigation:**

```hcl
# Chỉ tạo endpoints cho services có traffic lớn
# Single-AZ endpoints cho dev/lab
variable "endpoint_az_count" {
  default = 1  # Lab: 1 AZ only
  # Production: 3 AZs for HA
}

# Estimated cost với 1 AZ:
# 5 endpoints × 1 AZ × 24 × 30 × $0.01 = $36/month (save $72!)
```

**Cost impact:** $36–108/tháng tùy số AZs

---

### 🔪 Killer #4: CloudWatch Logs Ingestion ($0.50/GB)

**Vấn đề:** CloudWatch Logs charge $0.50/GB ingested ở ap-southeast-2. Verbose logging từ 10 services + OTel Collector + RDS logs = 5–10GB/ngày.

**Ví dụ thực tế:**

```
10 services × 200MB logs/day = 2GB
RDS slow query log = 500MB
MSK broker logs = 1GB
VPC Flow Logs = 2GB
OTel Collector debug = 1GB
Total: ~6.5GB/day × $0.50 = $97.5/month 😱
```

**Mitigation:**

```yaml
processors:
  filter/drop-health-checks:
    logs:
      exclude:
        match_type: regexp
        bodies:
          - ".*GET /health.*"

  filter/sample-10-percent:
    logs:
      include:
        match_type: strict
        severity_number:
          min: WARN  # Chỉ giữ WARNING+ERROR

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/order-service"
  retention_in_days = 7  # Không để 30 ngày!
}
```

**Cost impact:** $30–100/tháng nếu để default

---

### 🔪 Killer #5: CloudWatch Custom Metrics ($0.30/metric/month)

**Vấn đề:** 10 custom metrics đầu tiên FREE, từ metric thứ 11: $0.30/metric/month. OTel spanmetrics connector auto-generate hàng trăm metrics (per service × per endpoint × per status).

**Ví dụ thực tế:**

```
10 services × 5 endpoints × 3 status codes × 4 methods = 600 metrics!
600 metrics × $0.30 = $180/month 😱😱😱
```

**Mitigation:**

```yaml
processors:
  filter/drop-cardinality:
    metrics:
      exclude:
        match_type: regexp
        metric_names:
          - ".*.user_id.*"
          - ".*.session_id.*"
          - ".*.request_id.*"

connectors:
  spanmetrics:
    dimensions:
      - name: http.method
      - name: http.status_code
      - name: service.name
      # KHÔNG thêm: user_id, order_id, trace_id
```

**Cost impact:** $50–200/tháng nếu không filter cardinality

---

### 🔪 Killer #6: KMS API Calls ($1/million requests)

**Vấn đề:** KMS charge $1/million API requests sau 20,000 requests FREE đầu tiên. Mỗi RDS connection, Secrets Manager rotation, S3 object access đều gọi KMS.

**Mitigation:**

```hcl
resource "aws_kms_key" "rds" {
  rotation_period_in_days = 365  # Thay vì 90
  enable_key_rotation     = true
}

# Dùng AWS-managed keys (free) cho non-critical data
# aws/s3, aws/ebs, aws/rds - FREE API calls
```

**Cost impact:** Thường <$5/tháng, nhưng có thể spike nếu misconfigured

---

### 🔪 Killer #7: S3 PUT/GET Requests ($0.005/1000 PUTs)

**Vấn đề:** Loki/Tempo ghi logs/traces liên tục lên S3. Mỗi chunk = 1 PUT request.

**Ví dụ thực tế:**

```
Loki: 1,000 chunks/hour × 24h × 30d = 720,000 PUTs
Tempo: 500 chunks/hour × 24h × 30d = 360,000 PUTs
VPC Flow Logs: 100,000 PUTs
Total: ~1.2M PUTs × $0.005/1000 = $6/month
```

**Mitigation:**

```yaml
ingester:
  chunk_target_size: 1572864  # 1.5MB thay vì 256KB
  chunk_idle_period: 30m      # Flush mỗi 30 phút
  max_chunk_age: 1h
```

**Cost impact:** $5–20/tháng

---

### 🔪 Killer #8: MSK Minimum Cost (~$5/day)

**Vấn đề:** MSK Cluster luôn chạy 24/7 ngay cả khi không có traffic. 2 brokers × `kafka.t3.small` = $0.21/hr = **$151/month** 😱😱😱 — đây là resource tốn chi phí nhất trong lab!

**Mitigation:**

```bash
# scripts/msk-schedule.sh
ACTION=$1

if [ "$ACTION" = "down" ]; then
  cd environments/shared
  terraform apply -target=module.streaming -auto-approve -var="msk_enabled=false"
  echo "💰 MSK destroyed. Saving $5/day."
elif [ "$ACTION" = "up" ]; then
  cd environments/shared
  terraform apply -target=module.streaming -auto-approve -var="msk_enabled=true"
  echo "🚀 MSK restored. Cost: $5/day."
fi
```

> **Alternative:** Dùng self-hosted Kafka trên EC2/ECS (~$1/day) cho learning

**Cost impact:** $150/tháng nếu để chạy 24/7

---

### 🔪 Killer #9: Data Transfer Out to Internet ($0.114/GB)

**Vấn đề:** Traffic từ AWS ra Internet = $0.114/GB (ap-southeast-2). Grafana dashboard load, API responses, Docker image pulls từ bên ngoài.

**Ví dụ thực tế:**

```
Grafana dashboard: 50MB/load × 100 loads/day = 5GB/day
API responses: 2GB/day
Total: 7GB/day × $0.114 = $24/month
```

**Mitigation:**

```hcl
resource "aws_cloudfront_distribution" "web_ui" {
  default_cache_behavior {
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400   # 1 day
    default_ttl            = 604800  # 7 days
  }
}
```

**Cost impact:** $10–50/tháng

---

## 📋 Phần 2: Cost Breakdown Chi Tiết (Lab 10 Services)

### Baseline: Không Optimize (24/7, 3 AZs)

| Resource | Config | $/hr | $/day | $/month |
|---|---|---|---|---|
| NAT Gateway × 3 | HA per-AZ | $0.135 | $3.24 | $97 |
| MSK | 2 brokers t3.small | $0.210 | $5.04 | $151 |
| RDS PostgreSQL | db.t3.micro Multi-AZ | $0.036 | $0.86 | $26 |
| RDS Proxy | 100 connections | $0.015 | $0.36 | $11 |
| ElastiCache Redis | cache.t3.micro Multi-AZ | $0.034 | $0.82 | $25 |
| ALB | Internet-facing | $0.023 | $0.55 | $17 |
| ECS Fargate | 10 tasks × 0.5 vCPU | $0.180 | $4.32 | $130 |
| EFS | 20GB standard | $0.010 | $0.24 | $7 |
| Bastion | t3.micro | $0.010 | $0.24 | $7 |
| VPC Endpoints × 5 | 3 AZs | $0.150 | $3.60 | $108 |
| CloudWatch Logs | 6.5GB/day ingestion | — | $3.25 | $98 |
| CloudWatch Metrics | 100 custom | — | — | $30 |
| Route53 | 1 hosted zone + queries | — | — | $1 |
| Secrets Manager | 10 secrets | — | — | $4 |
| KMS | 5 keys + API calls | — | — | $5 |
| Data Transfer | Cross-AZ + Internet | — | — | $50 |
| **TOTAL** | | **$0.81** | **$22.52** | **$767 😱** |

### Optimized: Lab Hours Only (8h/day, single NAT, no MSK when idle)

| Resource | Config | $/hr | $/day (8h) | $/month |
|---|---|---|---|---|
| NAT Gateway × 1 | Single for lab | $0.045 | $0.36 | $11 |
| MSK | Destroyed when idle | $0 | $0 | $0 |
| RDS PostgreSQL | db.t3.micro Single-AZ | $0.018 | $0.14 | $4 |
| RDS Proxy | Disabled for lab | $0 | $0 | $0 |
| ElastiCache Redis | cache.t3.micro Single-AZ | $0.017 | $0.14 | $4 |
| ALB | Internet-facing | $0.023 | $0.18 | $5 |
| ECS Fargate | 6 tasks (lab only) | $0.110 | $0.88 | $26 |
| EFS | 5GB + IA transition | $0.005 | $0.04 | $1 |
| Bastion | Stopped when idle | $0 | $0 | $0 |
| VPC Endpoints × 3 | 1 AZ, essential only | $0.030 | $0.24 | $7 |
| CloudWatch Logs | 2GB/day (filtered) | — | $1.00 | $30 |
| CloudWatch Metrics | 10 custom (free tier) | — | — | $0 |
| Route53 | 1 hosted zone | — | — | $1 |
| Secrets Manager | 5 secrets | — | — | $2 |
| KMS | AWS-managed keys | — | — | $0 |
| Data Transfer | Minimized with endpoints | — | — | $10 |
| **TOTAL** | | **$0.25** | **$3.02** | **$101 ✅** |

> **Savings: $767 - $101 = $666/month (87% reduction) 🎉**

---

## 🤖 Phần 3: Automation Scripts — Schedule-Based Cost Control

### Script 1: Daily Start/Stop (Tiết kiệm 60%)

```bash
#!/bin/bash
# scripts/aws-schedule.sh
# Cron: 0 8 * * * /path/to/aws-schedule.sh up
#       0 23 * * * /path/to/aws-schedule.sh down

ACTION=$1
REGION="ap-southeast-2"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

if [ "$ACTION" = "down" ]; then
    log "🌙 Stopping lab resources..."

    for cluster in $(aws ecs list-clusters --query 'clusterArns[]' --output text); do
        for service in $(aws ecs list-services --cluster $cluster --query 'serviceArns[]' --output text); do
            aws ecs update-service --cluster $cluster --service $service --desired-count 0
            log "Stopped: $service"
        done
    done

    aws rds stop-db-instance --db-instance-identifier obs-rds --region $REGION

    INSTANCE_ID=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=obs-bastion" \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)
    aws ec2 stop-instances --instance-ids $INSTANCE_ID

    log "✅ Lab stopped. Cost: ~$0.50/day (RDS storage only)"

elif [ "$ACTION" = "up" ]; then
    log "☀️ Starting lab resources..."

    aws ec2 start-instances --instance-ids $INSTANCE_ID
    aws rds start-db-instance --db-instance-identifier obs-rds --region $REGION

    for cluster in $(aws ecs list-clusters --query 'clusterArns[]' --output text); do
        for service in $(aws ecs list-services --cluster $cluster --query 'serviceArns[]' --output text); do
            aws ecs update-service --cluster $cluster --service $service --desired-count 1
            log "Started: $service"
        done
    done

    log "✅ Lab started. Cost: ~$3/hour"
else
    echo "Usage: $0 {up|down}"
    exit 1
fi
```

### Script 2: Weekend Destroy (Tiết kiệm 90%)

```bash
#!/bin/bash
# scripts/weekend-destroy.sh
# Friday 11PM destroy, Monday 8AM restore

DAY_OF_WEEK=$(date +%u)

if [ "$DAY_OF_WEEK" -eq 5 ] && [ "$(date +%H)" -eq 23 ]; then
    cd terraform/environments/shared
    terraform destroy -auto-approve -var="keep_state=true"
    echo "🎉 Weekend mode: $0/month"
fi

if [ "$DAY_OF_WEEK" -eq 1 ] && [ "$(date +%H)" -eq 8 ]; then
    cd terraform/environments/shared
    terraform apply -auto-approve
    echo "🚀 Lab restored"
fi
```

### Script 3: Idle Detection Auto-Stop

```python
#!/usr/bin/env python3
# scripts/idle-detector.py

import boto3
import subprocess
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')

def get_traffic_last_2h():
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ApplicationELB',
        MetricName='RequestCount',
        Dimensions=[{'Name': 'LoadBalancer', 'Value': 'app/obs-alb'}],
        StartTime=datetime.utcnow() - timedelta(hours=2),
        EndTime=datetime.utcnow(),
        Period=3600,
        Statistics=['Sum']
    )
    return sum(p['Sum'] for p in response['Datapoints'])

if get_traffic_last_2h() < 10:
    print("😴 Lab idle > 2h, stopping...")
    subprocess.run(['./aws-schedule.sh', 'down'])
```

---

## 🎯 Phần 4: 7 Chiến Lược Optimization

### Strategy 1: Right-Sizing (Giảm 30–50%)

```bash
# Analyze ECS task utilization
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

```hcl
# Dynamic sizing dựa trên environment
variable "instance_tier" {
  default = "micro"  # lab | medium | large
}

locals {
  rds_instance_class = {
    "micro"  = "db.t3.micro"
    "medium" = "db.t3.medium"
    "large"  = "db.t3.large"
  }[var.instance_tier]
}
```

### Strategy 2: Graviton ARM Instances (Giảm 20%)

```hcl
# ECS Fargate với ARM
resource "aws_ecs_task_definition" "app" {
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  # Docker image phải build cho ARM:
  # FROM --platform=linux/arm64 python:3.12-slim
}

# RDS Graviton ('g' = Graviton, ~20% cheaper)
resource "aws_db_instance" "main" {
  instance_class = "db.t4g.micro"
}

# ElastiCache Graviton
resource "aws_elasticache_replication_group" "redis" {
  node_type = "cache.t4g.micro"
}
```

**Savings:** ~$20/month cho lab

### Strategy 3: Spot Instances (Giảm 70% cho batch workloads)

> Dùng cho: Traffic Generator, Chaos testing, Non-critical workers

```hcl
resource "aws_autoscaling_group" "spot" {
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
    instances {
      override { instance_type = "t3.medium" }
      override { instance_type = "t3a.medium" }  # AMD, even cheaper
    }
  }
}
```

> ⚠️ **Risk:** Spot có thể bị reclaim (2-minute warning) → chỉ dùng cho stateless workloads

### Strategy 4: S3 Intelligent-Tiering (Giảm 40% storage)

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "loki_tempo" {
  bucket = aws_s3_bucket.loki_tempo.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
    transition {
      days          = 90
      storage_class = "GLACIER_INSTANT_RETRIEVAL"
    }
    expiration {
      days = 365
    }
  }
}
```

### Strategy 5: EFS Lifecycle to IA (Giảm 92% storage)

```hcl
resource "aws_efs_file_system" "observability" {
  lifecycle_policy {
    transition_to_ia                    = "AFTER_30_DAYS"
    # Standard: $0.30/GB vs IA: $0.016/GB
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }
}
```

### Strategy 6: Reserved Instances (Khi stable)

> ⚠️ **Warning:** KHÔNG dùng RI cho lab khi mới bắt đầu! Flexibility quan trọng hơn savings.

Áp dụng khi lab chạy ổn định > 3 tháng:

```
1-year No Upfront RI:
- RDS db.t3.micro:         $15/month → $9/month  (40% off)
- ElastiCache cache.t3.micro: $12/month → $7/month  (42% off)

Compute Savings Plans (flexible):
- 1-year commitment, auto-apply cho ECS/EKS/Lambda
- 30-40% discount
```

### Strategy 7: Tag-Based Cost Allocation

```hcl
variable "required_tags" {
  type = map(string)
  default = {
    Project     = "observability-lab"
    Environment = "dev"
    Owner       = "dungtt"
    CostCenter  = "learning"
    AutoStop    = "true"
  }
}
```

```rego
# policy/general.rego — OPA enforce tagging
deny[msg] {
  not input.resource_changes[_].change.after.tags.Project
  msg := "Resource missing required tag: Project"
}
```

---

## 📈 Phần 5: Monitoring & Alerting

### AWS Budgets Setup

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "obs-lab-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["your-email@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["your-email@example.com"]
  }
}
```

### Cost Anomaly Detection

```hcl
resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "AWSServiceMonitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "daily" {
  name      = "daily-alert"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.service_monitor.arn]

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
      values        = ["50"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  subscriber {
    type    = "EMAIL"
    address = "your-email@example.com"
  }
}
```

### CloudWatch Billing Alarm

```hcl
resource "aws_cloudwatch_metric_alarm" "billing" {
  alarm_name          = "billing-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "21600"  # 6 hours
  statistic           = "Maximum"
  threshold           = "30"

  dimensions    = { Currency = "USD" }
  alarm_actions = [aws_sns_topic.billing.arn]
}
```

---

## 📅 Phần 6: Monthly Review Checklist

**Tuần 1: Cost Explorer Deep-Dive**
- [ ] Group by Service → Identify top 3 spenders
- [ ] Group by Usage Type → Find hidden costs
- [ ] So sánh với tháng trước → Identify spikes

**Tuần 2: Right-Sizing Review**
- [ ] Run AWS Compute Optimizer
- [ ] Review ECS task CPU/Memory utilization
- [ ] Review RDS Performance Insights
- [ ] Identify over-provisioned resources

**Tuần 3: Storage Cleanup**
- [ ] Review S3 buckets → Delete old logs/traces
- [ ] Review EBS snapshots → Delete unused
- [ ] Review ECR images → Apply lifecycle policy
- [ ] Review CloudWatch Logs → Reduce retention

**Tuần 4: Architecture Review**
- [ ] Review VPC Endpoints usage → Disable unused
- [ ] Review NAT Gateway traffic → Optimize routing
- [ ] Review Data Transfer costs → Keep within AZ
- [ ] Update `FINOPS.md` với lessons learned

---

## 🎓 Phần 7: Lab-Specific Tips

### Tip 1: "Apply sáng, Destroy tối"

```bash
# Alias trong ~/.bashrc
alias aws-lab-up='cd ~/terraform/environments/shared && terraform apply -auto-approve'
alias aws-lab-down='cd ~/terraform/environments/shared && terraform destroy -auto-approve'
```

> $3/hour × 8 hours = $24/day → ~$72/month thay vì $576/month (**87% savings**)

### Tip 2: MSK chỉ khi cần Kafka

```bash
# Bật MSK khi lab Kafka
terraform apply -target=module.streaming -var="msk_enabled=true"

# Tắt MSK khi xong
terraform apply -target=module.streaming -var="msk_enabled=false"
```

**Savings:** $150/tháng

### Tip 3: Dùng LocalStack cho dev/testing

```bash
# LocalStack = AWS mock trên Docker
docker run --rm -it -p 4566:4566 localstack/localstack

# Test Terraform modules không tốn $
export AWS_ENDPOINT_URL=http://localhost:4566
terraform plan
```

> **Use case:** Test module mới trước khi deploy lên AWS thật

### Tip 4: Free Tier Monitoring

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics USAGE_QUANTITY \
  --filter file://free-tier-filter.json
```

**AWS Free Tier (12 months):** 750h EC2 t2.micro, 750h RDS db.t2.micro, 5GB S3, 15GB Data Transfer out

---

## 📊 Phần 8: On-Prem vs AWS Cost Comparison

| Resource | On-Prem (Docker) | AWS (Optimized) | Trade-off |
|---|---|---|---|
| PostgreSQL | $0 (VM RAM) | $4/month (RDS) | AWS: auto-backup, failover |
| Redis | $0 (VM RAM) | $4/month (ElastiCache) | AWS: auto-failover |
| Kafka | $0 (VM RAM) | $0 (destroyed) hoặc $150 (MSK) | AWS: managed, but $ |
| Compute | $0 (VM CPU) | $26/month (Fargate) | AWS: auto-scaling, zero ops |
| Network | $0 (Docker bridge) | $11/month (NAT + endpoints) | AWS: VPC isolation |
| Storage | $0 (VM disk) | $1/month (EFS) | AWS: durability |
| Observability | $0 (self-host) | $30/month (CW Logs) | AWS: managed, integration |
| **TOTAL** | **$0** (đã mua VM) | **$76/month** | AWS: flexibility, learning |

> **Learning:** On-Prem rẻ hơn nhưng không scale được, không có DR, không có managed services. AWS đắt nhưng mang lại production-grade skills.

---

## 🚨 Phần 9: Common Gotchas & War Stories

### Gotcha 1: "The $1000 NAT Gateway Surprise"

**Story:** Junior engineer tạo VPC với 3 NAT Gateways "cho HA", để chạy 24/7.  
**Bill:** $32/NAT × 3 × 30 = **$2,880/năm** 😱  
**Lesson:** Lab dùng single NAT là đủ. Multi-AZ NAT chỉ khi traffic > 1TB/month.

### Gotcha 2: "The CloudWatch Cardinality Bomb"

**Story:** OTel spanmetrics với label `user_id` → 10,000 unique users = 10,000 metrics.  
**Bill:** 10,000 × $0.30 = **$3,000/tháng** 😱😱😱  
**Lesson:** KHÔNG BAO GIỜ dùng high-cardinality labels trong metrics. Chỉ dùng trong logs (Loki) và traces (Tempo).

### Gotcha 3: "The MSK Zombie"

**Story:** Tạo MSK cluster để test, quên destroy.  
**Bill:** $150/tháng × 6 tháng = **$900** cho cluster không ai dùng 😱  
**Lesson:** Đặt CloudWatch alarm cho MSK cost. Auto-destroy nếu không có traffic > 7 ngày.

### Gotcha 4: "The S3 Request Apocalypse"

**Story:** Loki config flush chunk mỗi 5 giây → 17,280 PUTs/ngày.  
**Bill:** 518,400 PUTs/month = **$78/tháng** just for PUTs  
**Lesson:** Tune `chunk_idle_period` ≥ 5 phút. Batch writes khi có thể.

---

## 🎯 Phần 10: FinOps Mindset — 5 Golden Rules

**Rule 1: "If you can't measure it, you can't optimize it"**  
→ Setup Cost Explorer + Budgets + tagging **TRƯỚC KHI** deploy

**Rule 2: "Destroy > Stop > Idle"**

| Action | Cost |
|---|---|
| `terraform destroy` | $0 |
| Stop (RDS/EC2) | Chỉ trả storage |
| Scale to 0 | Vẫn trả một phần |
| Running | Trả full |

**Rule 3: "Right-size from day 1"**  
→ Start with smallest instance, scale up when needed (không reverse!)

**Rule 4: "Automate or forget"**  
→ Mọi cost optimization phải được automate qua scripts/policies

**Rule 5: "Review monthly, optimize quarterly"**  
→ Monthly: review bill, identify spikes. Quarterly: right-size, architecture review. Yearly: Reserved Instances, Savings Plans.

---

## 🛠️ Tools & Scripts trong Repo này

| Tool | File | Purpose |
|---|---|---|
| AWS Schedule | `scripts/aws-schedule.sh` | Daily start/stop |
| Weekend Destroy | `scripts/weekend-destroy.sh` | Friday destroy, Monday restore |
| Idle Detector | `scripts/idle-detector.py` | Auto-stop khi idle > 2h |
| Cost Estimator | `scripts/cost-estimate.sh` | Estimate terraform plan cost |
| Tag Enforcer | `policy/general.rego` | OPA policy bắt buộc tagging |

---

## 📚 Further Reading

- [AWS Pricing Calculator](https://calculator.aws)
- [AWS Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar)
- [The FinOps Book](https://www.finops.org/resources/finops-book/)
- [Infracost](https://www.infracost.io/) — Terraform cost estimation trong CI/CD

---

> 🛡️ **"The cheapest resource is the one you don't use. The second cheapest is the one you use wisely."** — FinOps Foundation