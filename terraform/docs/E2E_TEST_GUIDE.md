# 🧪 E2E Test Guide — Shared Tooling for All Chaos Experiments

Tài liệu này là "single source of truth" cho việc tạo, chạy, và verify end-to-end traffic trong AWS Reliability Lab. Đây là công cụ hạ tầng (shared tooling) — giống như `aws-cli` hay `kubectl` — mà bạn phải build trước rồi mới dùng trong mọi Chaos Experiment từ POD 2 trở đi.

## 📋 Table of Contents

1. [Philosophy & Purpose](#-philosophy--purpose)
2. [The User Pain Score](#-the-user-pain-score)
3. [Three Approaches by POD](#️-three-approaches-by-pod)
4. [Approach 1: Python Script (POD 1)](#-approach-1-python-script-pod-1)
5. [Approach 2: Traffic Generator Service (POD 2+)](#-approach-2-traffic-generator-service-pod-2)
6. [Approach 3: AWS FIS Integration (POD 3)](#-approach-3-aws-fis-integration-pod-3)
7. [X-Ray Verification Guide](#-x-ray-verification-guide)
8. [Integration with Chaos Playbook](#-integration-with-chaos-playbook)
9. [Troubleshooting](#-troubleshooting)

---

## 🎯 Philosophy & Purpose

### Tại sao cần E2E Test?

Trong Chaos Engineering, bạn KHÔNG THỂ đo "User Pain Score = 5%" nếu bạn không có baseline "trước khi chaos, success rate = 100%". E2E Test Script chính là công cụ tạo ra baseline đó.

**Nguyên tắc SRE:**

> "Bạn không thể test một hệ thống mà bạn không nhìn thấy."

Nếu bạn chạy Chaos Drill mà không có E2E traffic:

- ❌ Không biết hệ thống có thực sự phục hồi không
- ❌ Không đo được impact lên user experience
- ❌ Không verify được X-Ray trace xuyên suốt
- ❌ Không phân biệt được "service chết" vs "service sống nhưng không serve traffic"

### E2E Test vs Chaos Experiment

| Aspect | E2E Test Script (Tool) | Chaos Experiment |
|--------|------------------------|-------------------|
| Bản chất | Công cụ tạo traffic + verify | Hành động "phá" hệ thống |
| Khi nào chạy | TRƯỚC, TRONG, SAU mọi experiment | Chỉ chạy khi inject failure |
| Ví dụ | Python script bắn 100 requests `/order` | `aws rds reboot-db-instance --force-failover` |
| Đo gì | Baseline: "Hệ thống khỏe mạnh trông như thế nào?" | Impact: "Hệ thống bị tổn thương bao nhiêu?" |

---

## 📊 The User Pain Score

### Definition

**User Pain Score = % successful orders trong thời gian chaos.**

Đây là metric quan trọng nhất để đánh giá resilience của hệ thống, vì nó đo trải nghiệm thực tế của user, không phải trạng thái của service.

### Formula

```
User Pain Score = (1 - success_count / total_count) × 100
```

### Thresholds

| Pain Score | Severity | Interpretation |
|-----------|---------|-----------------|
| 0-5% | ✅ Good | User hầu như không nhận thấy sự cố |
| 5-20% | ⚠️ Degraded | Một số user bị ảnh hưởng, cần investigate |
| >20% | 🚨 Critical | Outage nghiêm trọng, cần immediate action |

### Example

**Scenario: RDS Multi-AZ Failover (60s)**

- Total requests: 100
- Success: 95
- Failed: 5 (timeout trong 60s failover)
- User Pain Score = 5% → ✅ Good (hệ thống self-healing tốt)

**Scenario: Payment Service Down (không có Circuit Breaker)**

- Total requests: 100
- Success: 0
- Failed: 100
- User Pain Score = 100% → 🚨 Critical (complete outage)

---

## 🗺️ Three Approaches by POD

### Timeline

| POD | Approach | When to Use | Complexity |
|-----|---------|--------------|-----------|
| POD 1 | Python Script | Milestone 1 (AMP + X-Ray setup) | Low |
| POD 2 | Traffic Generator Service | Từ POD 2 trở đi (có RDS + MSK) | Medium |
| POD 3 | AWS FIS Integration | Từ POD 3 trở đi (automated chaos) | High |

### Decision Tree

```
Bạn đang ở đâu?
├─ POD 1 (chỉ có Order + Payment + AMP + X-Ray)
│  └─ Dùng Approach 1: Python Script
│
├─ POD 2 (có RDS + MSK + 6 services)
│  └─ Dùng Approach 2: Traffic Generator Service
│
└─ POD 3 (có AWS FIS)
   └─ Dùng Approach 3: FIS + Traffic Generator
```

---

## 🐍 Approach 1: Python Script (POD 1)

### Mục đích

Dùng cho Milestone 1 (POD 1 - The Illumination) để verify:

- ✅ AMP nhận metrics từ Order + Payment services
- ✅ X-Ray có traces xuyên suốt Order → Payment → RDS
- ✅ ADOT Sidecar hoạt động đúng

### Khi nào dùng

- Phase 1.5: Verify AMP + X-Ray + ADOT
- Chaos Experiments 1-6 (Phase 1)
- Chaos Experiments 7-10 (Phase 1.5)

### Setup

**Prerequisites:**

```bash
# Install dependencies
pip install requests boto3

# Configure AWS CLI (nếu chưa)
aws configure
```

**Script: `e2e_test_pod1.py`**

```python
#!/usr/bin/env python3
"""
E2E Test Script for POD 1 (Phase 1.5)
Target: Order Service + Payment Service via Cloud Map DNS
"""

import requests
import time
import json
import boto3
from datetime import datetime, timedelta
from collections import defaultdict

# Configuration
ORDER_SERVICE_URL = "http://order-service.ecommerce.local:5001"
NUM_REQUESTS = 100
DELAY_BETWEEN_REQUESTS = 0.5  # seconds

# X-Ray client
xray_client = boto3.client('xray', region_name='ap-southeast-2')

def run_e2e_test():
    """Run E2E test and collect metrics"""
    print(f"🚀 Starting E2E Test: {NUM_REQUESTS} requests to Order Service")
    print(f"   Target: {ORDER_SERVICE_URL}/process")
    print(f"   Delay: {DELAY_BETWEEN_REQUESTS}s between requests")
    print()
    
    stats = {
        'total': 0,
        'success': 0,
        'failed': 0,
        'status_codes': defaultdict(int),
        'latencies': [],
        'errors': []
    }
    
    start_time = time.time()
    
    for i in range(NUM_REQUESTS):
        try:
            # Generate random product_id (1-5) and quantity (1-3)
            payload = {
                'product_id': (i % 5) + 1,
                'quantity': (i % 3) + 1
            }
            
            # Send request
            req_start = time.time()
            response = requests.post(
                f"{ORDER_SERVICE_URL}/process",
                json=payload,
                timeout=10
            )
            req_duration = time.time() - req_start
            
            # Collect stats
            stats['total'] += 1
            stats['status_codes'][response.status_code] += 1
            stats['latencies'].append(req_duration)
            
            if response.status_code == 200:
                stats['success'] += 1
                print(f"  ✅ [{i+1}/{NUM_REQUESTS}] 200 OK - {req_duration:.3f}s")
            else:
                stats['failed'] += 1
                error_msg = f"HTTP {response.status_code}: {response.text[:100]}"
                stats['errors'].append(error_msg)
                print(f"  ❌ [{i+1}/{NUM_REQUESTS}] {response.status_code} - {req_duration:.3f}s")
        
        except requests.exceptions.Timeout:
            stats['total'] += 1
            stats['failed'] += 1
            stats['errors'].append("Timeout")
            print(f"  ⏱️  [{i+1}/{NUM_REQUESTS}] Timeout")
        
        except Exception as e:
            stats['total'] += 1
            stats['failed'] += 1
            stats['errors'].append(str(e))
            print(f"  💥 [{i+1}/{NUM_REQUESTS}] Error: {e}")
        
        # Delay between requests
        time.sleep(DELAY_BETWEEN_REQUESTS)
    
    total_duration = time.time() - start_time
    
    # Calculate metrics
    success_rate = (stats['success'] / stats['total'] * 100) if stats['total'] > 0 else 0
    pain_score = 100 - success_rate
    avg_latency = sum(stats['latencies']) / len(stats['latencies']) if stats['latencies'] else 0
    
    # Print report
    print()
    print("=" * 60)
    print("📊 E2E TEST REPORT")
    print("=" * 60)
    print(f"Total Requests:    {stats['total']}")
    print(f"Success:           {stats['success']}")
    print(f"Failed:            {stats['failed']}")
    print(f"Success Rate:      {success_rate:.2f}%")
    print(f"User Pain Score:   {pain_score:.2f}%")
    print(f"Avg Latency:       {avg_latency:.3f}s")
    print(f"Total Duration:    {total_duration:.2f}s")
    print()
    print("Status Codes:")
    for code, count in sorted(stats['status_codes'].items()):
        print(f"  {code}: {count}")
    print()
    
    if stats['errors']:
        print(f"Errors ({len(stats['errors'])}):")
        for error in stats['errors'][:5]:  # Show first 5 errors
            print(f"  - {error}")
        if len(stats['errors']) > 5:
            print(f"  ... and {len(stats['errors']) - 5} more")
    print()
    
    # Save report to JSON
    report = {
        'timestamp': datetime.now().isoformat(),
        'num_requests': NUM_REQUESTS,
        'stats': stats,
        'success_rate': success_rate,
        'pain_score': pain_score,
        'avg_latency': avg_latency,
        'total_duration': total_duration
    }
    
    with open('e2e_test_report.json', 'w') as f:
        json.dump(report, f, indent=2, default=str)
    
    print(f"✅ Report saved to: e2e_test_report.json")
    print()
    
    return stats

def verify_xray_traces(minutes=5):
    """Verify X-Ray traces for the test period"""
    print(f"🔍 Verifying X-Ray traces (last {minutes} minutes)...")
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=minutes)
    
    try:
        # Get trace summaries
        response = xray_client.get_trace_summaries(
            StartTime=start_time,
            EndTime=end_time,
            Sampling=False
        )
        
        traces = response.get('TraceSummaries', [])
        
        print(f"  Found {len(traces)} traces")
        
        # Count traces by service
        service_counts = defaultdict(int)
        for trace in traces:
            services = trace.get('Services', [])
            for service in services:
                service_name = service.get('Name', 'unknown')
                service_counts[service_name] += 1
        
        if service_counts:
            print("  Traces by service:")
            for service, count in sorted(service_counts.items(), key=lambda x: x[1], reverse=True):
                print(f"    {service}: {count}")
        
        # Check for specific trace pattern: Order → Payment
        order_to_payment = 0
        for trace in traces:
            services = [s.get('Name') for s in trace.get('Services', [])]
            if 'order-service' in services and 'payment-service' in services:
                order_to_payment += 1
        
        print(f"  Order → Payment traces: {order_to_payment}")
        print()
        
        return len(traces)
    
    except Exception as e:
        print(f"  ❌ Error querying X-Ray: {e}")
        return 0

if __name__ == "__main__":
    print("=" * 60)
    print("🧪 E2E TEST - POD 1 (Phase 1.5)")
    print("=" * 60)
    print()
    
    # Run E2E test
    stats = run_e2e_test()
    
    # Verify X-Ray traces
    trace_count = verify_xray_traces(minutes=5)
    
    print("=" * 60)
    print("✅ E2E TEST COMPLETE")
    print("=" * 60)
    print()
    print("Next steps:")
    print("  1. Check AMP for metrics: http://<amp-workspace-url>")
    print("  2. Check X-Ray Service Map: AWS Console → X-Ray")
    print("  3. Review report: cat e2e_test_report.json")
    print()
```

### Usage

```bash
# Run from your local machine (must have network access to VPC)
# Or run from Bastion Host / EC2 in the same VPC

python e2e_test_pod1.py
```

### Expected Output

```
============================================================
🧪 E2E TEST - POD 1 (Phase 1.5)
============================================================

🚀 Starting E2E Test: 100 requests to Order Service
   Target: http://order-service.ecommerce.local:5001/process
   Delay: 0.5s between requests

  ✅ [1/100] 200 OK - 0.234s
  ✅ [2/100] 200 OK - 0.198s
  ...
  ✅ [100/100] 200 OK - 0.212s

============================================================
📊 E2E TEST REPORT
============================================================
Total Requests:    100
Success:           100
Failed:            0
Success Rate:      100.00%
User Pain Score:   0.00%
Avg Latency:       0.215s
Total Duration:    52.34s

Status Codes:
  200: 100

✅ Report saved to: e2e_test_report.json

🔍 Verifying X-Ray traces (last 5 minutes)...
  Found 100 traces
  Traces by service:
    order-service: 100
    payment-service: 100
  Order → Payment traces: 100

============================================================
✅ E2E TEST COMPLETE
============================================================

Next steps:
  1. Check AMP for metrics: http://<amp-workspace-url>
  2. Check X-Ray Service Map: AWS Console → X-Ray
  3. Review report: cat e2e_test_report.json
```

---

## 🚦 Approach 2: Traffic Generator Service (POD 2+)

### Mục đích

Dùng cho POD 2 trở đi (khi đã có RDS + MSK + 6 services) để:

- ✅ Tạo realistic traffic patterns (browse, order, flash sale)
- ✅ Đo User Pain Score trong Chaos Experiments
- ✅ Verify Kafka event flow (Order → Workers)
- ✅ Tích hợp với Grafana dashboards

### Khi nào dùng

- Phase 2: The Critical Path (6 services)
- Chaos Experiments 11-15 (POD 2 - Stateful Chaos)
- Làm baseline cho POD 3

### Architecture

```
Traffic Generator (:5003)
├─ REST API: /start, /stop, /status
├─ Prometheus metrics: /metrics
└─ Scenarios:
   ├─ normal (balanced traffic)
   ├─ flash_sale (high-volume orders)
   ├─ browse_heavy (mostly browsing)
   ├─ health_check (continuous health checks)
   └─ event_driven (orders + verify Kafka workers)
```

### Deploy Traffic Generator

**Step 1: Build & Push Docker Image**

```bash
cd on-premises/applications-vm/applications/traffic-gen

# Build image
docker build -t traffic-gen:v1 .

# Tag for ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-southeast-2.amazonaws.com

docker tag traffic-gen:v1 <account-id>.dkr.ecr.ap-southeast-2.amazonaws.com/obs/traffic-gen:v1

# Push to ECR
docker push <account-id>.dkr.ecr.ap-southeast-2.amazonaws.com/obs/traffic-gen:v1
```

**Step 2: Create Terraform Module**

File: `terraform/data-plane/traffic-gen/main.tf`

```hcl
#--------------------------------------------------------------
# DATA PLANE — TRAFFIC GENERATOR
#--------------------------------------------------------------

# Read metadata from SSM (same pattern as Order/Payment services)
data "aws_ssm_parameter" "private_subnets" {
  name = "/obs/lab/network/private_subnets"
}

data "aws_ssm_parameter" "app_sg_id" {
  name = "/obs/lab/security/app_sg_id"
}

data "aws_ssm_parameter" "task_execution_role" {
  name = "/obs/lab/iam/task_execution_role_arn"
}

data "aws_ssm_parameter" "task_role" {
  name = "/obs/lab/iam/task_role_arn"
}

data "aws_ssm_parameter" "ecs_cluster_id" {
  name = "/obs/lab/compute/ecs_cluster_id"
}

data "aws_ssm_parameter" "cloudmap_namespace" {
  name = "/obs/lab/compute/cloudmap_namespace_id"
}

data "aws_ssm_parameter" "ecr_url" {
  name = "/obs/lab/ecr/traffic-gen"
}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnets.value)
  traffic_gen_image  = format("%s:%s", data.aws_ssm_parameter.ecr_url.value, var.image_tag)
}

#--------------------------------------------------------------
# DEPLOY ECS SERVICE
#--------------------------------------------------------------
module "traffic_gen" {
  source = "../../modules/compute/ecs-service"

  project_name   = var.project_name
  service_name   = "traffic-gen"
  cluster_id     = data.aws_ssm_parameter.ecs_cluster_id.value
  image          = local.traffic_gen_image
  container_port = 5003

  subnets         = local.private_subnet_ids
  security_groups = [data.aws_ssm_parameter.app_sg_id.value]

  execution_role_arn = data.aws_ssm_parameter.task_execution_role.value
  task_role_arn      = data.aws_ssm_parameter.task_role.value

  # Service Discovery (Cloud Map)
  enable_service_discovery = true
  namespace_id             = data.aws_ssm_parameter.cloudmap_namespace.value

  # Sizing
  cpu    = 256
  memory = 512

  # Environment Variables
  environment = {
    SERVICE_NAME = "traffic-gen"
    PORT         = "5003"
  }

  common_tags = {
    Module  = "ecs-service"
    Service = "traffic-gen"
    Plane   = "Data"
  }
}
```

File: `terraform/data-plane/traffic-gen/variables.tf`

```hcl
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "obs"
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "v1"
}
```

**Step 3: Deploy**

```bash
cd terraform/data-plane/traffic-gen
terraform init
terraform apply -auto-approve
```

**Step 4: Verify Deployment**

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster obs-cluster \
  --services traffic-gen \
  --query 'services[0].{Status:status, Running:runningCount, Desired:desiredCount}' \
  --output table

# Expected: ACTIVE, 1, 1

# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster obs-cluster \
  --service-name traffic-gen \
  --query 'taskArns[0]' \
  --output text)

# Get task IP
TASK_IP=$(aws ecs describe-tasks \
  --cluster obs-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].containers[0].networkInterfaces[0].privateIpv4Address' \
  --output text)

echo "Traffic Generator IP: $TASK_IP"
```

### Usage

**Start Traffic**

```bash
# Normal traffic (2 req/s for 10 minutes)
curl -X POST http://$TASK_IP:5003/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "normal",
    "rate": 2,
    "duration": 600
  }'

# Flash sale (10 req/s for 5 minutes)
curl -X POST http://$TASK_IP:5003/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "flash_sale",
    "rate": 10,
    "duration": 300
  }'
```

**Check Status**

```bash
curl http://$TASK_IP:5003/status | jq
```

Expected Output:

```json
{
  "running": true,
  "scenario": "normal",
  "rate": 2,
  "duration": 600,
  "stats": {
    "total": 45,
    "success": 45,
    "errors": 0,
    "elapsed": 23.5
  }
}
```

**Stop Traffic**

```bash
curl -X POST http://$TASK_IP:5003/stop
```

**Get Prometheus Metrics**

```bash
curl http://$TASK_IP:5003/metrics
```

Expected Output:

```
# HELP traffic_gen_running Whether the traffic generator is running
# TYPE traffic_gen_running gauge
traffic_gen_running 1

# HELP traffic_gen_requests_total Total requests sent
# TYPE traffic_gen_requests_total counter
traffic_gen_requests_total{result="success"} 45
traffic_gen_requests_total{result="error"} 0
```

### Integration with Chaos Experiments

**Pre-flight Checklist (Before Chaos Drill)**

```bash
# 1. Start Traffic Generator (baseline)
curl -X POST http://$TASK_IP:5003/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "normal",
    "rate": 2,
    "duration": 1800
  }'

# 2. Wait 1 minute for baseline
sleep 60

# 3. Check baseline stats
curl http://$TASK_IP:5003/status | jq '.stats'
# Expected: success rate = 100%

# 4. NOW inject chaos (e.g., RDS failover)
aws rds reboot-db-instance \
  --db-instance-identifier obs-lab-postgres \
  --force-failover

# 5. Monitor User Pain Score during chaos
watch -n 5 'curl -s http://$TASK_IP:5003/status | jq ".stats"'

# 6. After chaos, check final stats
curl http://$TASK_IP:5003/status | jq
```

---

## 🌪️ Approach 3: AWS FIS Integration (POD 3)

### Mục đích

Dùng cho POD 3 - The Chaos Dojo để:

- ✅ Tự động hóa hoàn toàn Chaos Experiments
- ✅ Tích hợp Traffic Generator vào FIS Experiment Template
- ✅ Auto-stop khi CloudWatch Alarm trigger
- ✅ Collect metrics trước/sau chaos

### Khi nào dùng

- Phase 2.7: The AWS Chaos Dojo
- Chaos Experiments 16-21 (POD 3 - Full-Stack Chaos)
- Game Days / Production Chaos

### Architecture

```
AWS FIS Experiment Template
├─ Pre-action: Start Traffic Generator
├─ Action: Inject failure (RDS failover, AZ failure, etc.)
├─ Stop condition: CloudWatch Alarm (e.g., ErrorRate > 20%)
└─ Post-action: Stop Traffic Generator, collect stats
```

### Create FIS Experiment Template

**Step 1: Create IAM Role for FIS**

File: `terraform/modules/fis/main.tf`

```hcl
#--------------------------------------------------------------
# FIS Experiment Role
#--------------------------------------------------------------
resource "aws_iam_role" "fis_experiment" {
  name = "${var.project_name}-fis-experiment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies for FIS actions
resource "aws_iam_role_policy_attachment" "fis_ec2" {
  role       = aws_iam_role.fis_experiment.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "fis_rds" {
  role       = aws_iam_role.fis_experiment.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "fis_ecs" {
  role       = aws_iam_role.fis_experiment.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# Custom policy for SSM (to run commands on Traffic Generator)
resource "aws_iam_role_policy" "fis_ssm" {
  name = "${var.project_name}-fis-ssm-policy"
  role = aws_iam_role.fis_experiment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:CancelCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })
}
```

**Step 2: Create FIS Experiment Template**

File: `terraform/modules/fis/experiments.tf`

```hcl
#--------------------------------------------------------------
# Experiment 16: The AZ Apocalypse
#--------------------------------------------------------------
resource "aws_fis_experiment_template" "az_apocalypse" {
  description = "Simulate AZ failure and measure User Pain Score"

  # Stop condition: Error rate > 20%
  stop_condition {
    max_duration = 600  # 10 minutes max
  }

  # Action 1: Start Traffic Generator (pre-action)
  action "start_traffic" {
    action_id     = "aws:ssm:send-command"
    description   = "Start Traffic Generator"

    target {
      resource_type = "aws:ec2:instance"
      resource_arns = [var.traffic_gen_instance_arn]
    }

    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:ap-southeast-2::document/AWS-RunShellScript"
    }

    parameter {
      key   = "parameters"
      value = jsonencode({
        commands = [
          "curl -X POST http://localhost:5003/start -H 'Content-Type: application/json' -d '{\"scenario\":\"normal\",\"rate\":2,\"duration\":600}'"
        ]
      })
    }
  }

  # Action 2: Stop EC2 instances in AZ-a
  action "stop_az" {
    action_id     = "aws:ec2:stop-instances"
    description   = "Stop all EC2 instances in AZ-a"

    target {
      resource_type = "aws:ec2:instance"
      resource_arns = var.az_a_instance_arns
    }

    parameter {
      key   = "startAfter"
      value = "start_traffic"
    }
  }

  # Action 3: Stop Traffic Generator (post-action)
  action "stop_traffic" {
    action_id     = "aws:ssm:send-command"
    description   = "Stop Traffic Generator"

    target {
      resource_type = "aws:ec2:instance"
      resource_arns = [var.traffic_gen_instance_arn]
    }

    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:ap-southeast-2::document/AWS-RunShellScript"
    }

    parameter {
      key   = "parameters"
      value = jsonencode({
        commands = [
          "curl -X POST http://localhost:5003/stop",
          "curl http://localhost:5003/status > /tmp/traffic_stats.json"
        ]
      })
    }

    parameter {
      key   = "startAfter"
      value = "stop_az"
    }
  }

  # Target: EC2 instances in AZ-a
  target "az_a_instances" {
    resource_type  = "aws:ec2:instance"
    selection_mode = "ALL"

    resource_tag {
      key   = "AvailabilityZone"
      value = "ap-southeast-2a"
    }
  }

  # Log configuration
  log_configuration {
    cloudwatch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.fis_logs.arn
    }
  }

  role_arn = aws_iam_role.fis_experiment.arn

  tags = {
    Name = "az-apocalypse"
    POD  = "3"
  }
}

# CloudWatch Log Group for FIS
resource "aws_cloudwatch_log_group" "fis_logs" {
  name              = "/aws/fis/experiments"
  retention_in_days = 30
}
```

**Step 3: Run FIS Experiment**

```bash
# Start experiment
aws fis start-experiment \
  --experiment-template-id <template-id>

# Monitor experiment
aws fis get-experiment \
  --id <experiment-id> \
  --query 'experiment.{State:state.status, StartTime:startTime, EndTime:endTime}'

# Get experiment report
aws fis get-experiment \
  --id <experiment-id> \
  --query 'experiment.experimentReport'
```

---

## 🔍 X-Ray Verification Guide

### Query Traces via AWS CLI

**Get Trace Summaries**

```bash
# Last 5 minutes
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'TraceSummaries[*].{Id:Id, Duration:Duration, Services:Services[*].Name}' \
  --output table
```

**Filter by Service**

```bash
# Only Order Service traces
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --filter-expression 'service(id(name: "order-service"))' \
  --query 'TraceSummaries[*].{Id:Id, Duration:Duration}' \
  --output table
```

**Filter by Status**

```bash
# Only error traces
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --filter-expression 'fault = true OR error = true' \
  --query 'TraceSummaries[*].{Id:Id, Duration:Duration, Fault:fault, Error:error}' \
  --output table
```

### Verify Trace Flow

Expected trace flow for Order creation:

```
User → API Gateway → Order Service → Payment Service → RDS
                                      ↓
                                    Kafka → Notification Worker
                                      ↓
                                    Inventory Worker
```

**Verification script:**

```bash
#!/bin/bash
# verify_trace_flow.sh

TRACE_ID=$1

if [ -z "$TRACE_ID" ]; then
  echo "Usage: ./verify_trace_flow.sh <trace-id>"
  exit 1
fi

echo "🔍 Verifying trace flow for: $TRACE_ID"
echo

# Get trace details
TRACE=$(aws xray batch-get-traces \
  --trace-ids $TRACE_ID \
  --query 'Traces[0]')

# Extract services
SERVICES=$(echo $TRACE | jq -r '.Segments[].Document | fromjson | .name' | sort | uniq)

echo "Services in trace:"
echo "$SERVICES"
echo

# Check for expected services
EXPECTED_SERVICES=("order-service" "payment-service")
MISSING=()

for service in "${EXPECTED_SERVICES[@]}"; do
  if echo "$SERVICES" | grep -q "$service"; then
    echo "✅ $service found"
  else
    echo "❌ $service NOT found"
    MISSING+=("$service")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo
  echo "✅ All expected services present in trace"
else
  echo
  echo "❌ Missing services: ${MISSING[*]}"
fi
```

---

## 📚 Integration with Chaos Playbook

### Mapping Table

| Experiment | POD | E2E Approach | User Pain Score Target |
|-----------|-----|---------------|--------------------------|
| **Phase 1: The Sync Tracer Bullet** | | | |
| Exp 1: IAM Blackhole | 1 | Python Script | < 5% |
| Exp 2: Network Partition | 1 | Python Script | < 10% |
| Exp 3: Poison Config | 1 | Python Script | < 5% |
| **Phase 1.5: The Illumination** | | | |
| Exp 7: Trace Storm | 1 | Python Script | 0% (no user impact) |
| Exp 8: Silent Blinder | 1 | Python Script | 0% (telemetry only) |
| Exp 9: Cardinality Bomb | 1 | Python Script | 0% (cost only) |
| Exp 10: Zombie Sidecar | 1 | Python Script | 0% (telemetry only) |
| **Phase 2: The Critical Path** | | | |
| Exp 11: RDS Failover | 2 | Traffic Generator | < 5% |
| Exp 12: Cache Avalanche | 2 | Traffic Generator | < 10% |
| Exp 13: Kafka Partition | 2 | Traffic Generator | < 5% |
| Exp 14: Zombie Consumer | 2 | Traffic Generator | < 5% |
| Exp 15: Graceful Guillotine | 2 | Traffic Generator | 0% |
| **Phase 2.7: The Chaos Dojo** | | | |
| Exp 16: AZ Apocalypse | 3 | FIS + Traffic Gen | < 10% |
| Exp 17: Cascade Symphony | 3 | FIS + Traffic Gen | < 15% |
| Exp 18: Secret Betrayal | 3 | FIS + Traffic Gen | 0% |
| Exp 19-21: Stateful Chaos | 3 | FIS + Traffic Gen | < 10% |

### Example: Exp 11 (RDS Failover) with E2E Test

```bash
#!/bin/bash
# exp11_rds_failover.sh

echo "============================================================"
echo "🧪 Experiment 11: The DB Earthquake (RDS Multi-AZ Failover)"
echo "============================================================"
echo

# Step 1: Pre-flight - Start Traffic Generator
echo "Step 1: Starting Traffic Generator (baseline)..."
curl -X POST http://$TRAFFIC_GEN_IP:5003/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "normal",
    "rate": 2,
    "duration": 600
  }'
echo

# Step 2: Wait for baseline (1 minute)
echo "Step 2: Waiting 60s for baseline..."
sleep 60

# Step 3: Check baseline stats
echo "Step 3: Checking baseline stats..."
BASELINE=$(curl -s http://$TRAFFIC_GEN_IP:5003/status | jq '.stats')
echo "Baseline: $BASELINE"
echo

# Step 4: Inject chaos - RDS failover
echo "Step 4: Injecting chaos - RDS Multi-AZ Failover..."
aws rds reboot-db-instance \
  --db-instance-identifier obs-lab-postgres \
  --force-failover
echo "⏰ Failover initiated at $(date)"
echo

# Step 5: Monitor during chaos (every 10s for 2 minutes)
echo "Step 5: Monitoring User Pain Score during chaos..."
for i in {1..12}; do
  echo "[$i/12] $(date +%H:%M:%S)"
  STATS=$(curl -s http://$TRAFFIC_GEN_IP:5003/status | jq '.stats')
  TOTAL=$(echo $STATS | jq '.total')
  SUCCESS=$(echo $STATS | jq '.success')
  if [ $TOTAL -gt 0 ]; then
    PAIN_SCORE=$(echo "scale=2; (1 - $SUCCESS / $TOTAL) * 100" | bc)
    echo "  User Pain Score: $PAIN_SCORE%"
  fi
  sleep 10
done
echo

# Step 6: Check final stats
echo "Step 6: Checking final stats..."
FINAL=$(curl -s http://$TRAFFIC_GEN_IP:5003/status | jq '.stats')
echo "Final: $FINAL"
echo

# Step 7: Stop Traffic Generator
echo "Step 7: Stopping Traffic Generator..."
curl -X POST http://$TRAFFIC_GEN_IP:5003/stop
echo

# Step 8: Verify X-Ray traces
echo "Step 8: Verifying X-Ray traces..."
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'length(TraceSummaries)'
echo

echo "============================================================"
echo "✅ Experiment 11 Complete"
echo "============================================================"
```

---

## 🔧 Troubleshooting

### Issue 1: Cloud Map DNS Not Resolving

**Symptom:**

```
requests.exceptions.ConnectionError: HTTPConnectionPool(host='order-service.ecommerce.local', port=5001): Max retries exceeded
```

**Solution:**

```bash
# Check Cloud Map service
aws servicediscovery list-services \
  --query 'Services[*].{Name:Name, Id:Id}' \
  --output table

# Check instances
aws servicediscovery list-instances \
  --service-id <service-id> \
  --query 'Instances[*].{Id:Id, IP:Attributes.AWS_INSTANCE_IPV4}' \
  --output table

# Test DNS resolution from within VPC
aws ecs execute-command \
  --cluster obs-cluster \
  --task <task-arn> \
  --container order-service \
  --interactive \
  --command "nslookup order-service.ecommerce.local"
```

### Issue 2: X-Ray Traces Not Appearing

**Symptom:**

- E2E test runs successfully
- But X-Ray Service Map shows no traces

**Solution:**

```bash
# Check ADOT sidecar logs
aws logs tail /ecs/otel-sidecar --since 5m --follow

# Check IAM permissions
aws iam get-role-policy \
  --role-name obs-lab-ecs-task-role \
  --policy-name obs-ecs-task-xray

# Expected: xray:PutTraceSegments, xray:PutTelemetryRecords

# Verify ADOT config
aws ecs describe-task-definition \
  --task-definition obs-lab-order-service \
  --query 'taskDefinition.containerDefinitions[?name==`aws-otel-collector`].environment' \
  --output json
```

### Issue 3: Traffic Generator Timeout

**Symptom:**

```
requests.exceptions.Timeout: HTTPConnectionPool(host='traffic-gen.ecommerce.local', port=5003): Read timed out
```

**Solution:**

```bash
# Check Traffic Generator service status
aws ecs describe-services \
  --cluster obs-cluster \
  --services traffic-gen \
  --query 'services[0].{Status:status, Running:runningCount}' \
  --output table

# Check Security Group
aws ec2 describe-security-groups \
  --group-ids <app-sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5003`]' \
  --output json

# Expected: Ingress rule allowing port 5003 from App SG
```

### Issue 4: User Pain Score = 100%

**Symptom:**

- All requests fail
- User Pain Score = 100%

**Solution:**

```bash
# Check if services are running
for svc in order-service payment-service; do
  echo "=== $svc ==="
  aws ecs describe-services \
    --cluster obs-cluster \
    --services $svc \
    --query 'services[0].{Status:status, Running:runningCount}' \
    --output table
done

# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier obs-lab-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus, Endpoint:Endpoint.Address}' \
  --output table

# Check CloudWatch Alarms
aws cloudwatch describe-alarms \
  --alarm-names obs-lab-order-service-running-task-low \
  --query 'MetricAlarms[0].{State:StateValue, Reason:StateReason}' \
  --output table
```

---

## 📖 References

- Chaos Playbook: [AWS_CHAOS_PLAYBOOK.md](AWS_CHAOS_PLAYBOOK.md)
- Roadmap: [ROADMAP.md](../ROADMAP.md)
- Architecture: [ARCHITECTURE.md](../ARCHITECTURE.md)
- Traffic Generator Code: [traffic-gen](../../on-premises/applications-vm/applications/traffic-gen/app.py)
- [AWS FIS Documentation](https://docs.aws.amazon.com/fis/)
- [X-Ray Documentation](https://docs.aws.amazon.com/xray/)

---

## 🎓 Key Takeaways

1. E2E Test là "shared tooling", không phải Chaos Experiment
2. User Pain Score là metric quan trọng nhất để đánh giá resilience
3. 3 Approaches tăng dần về độ phức tạp: Python Script → Traffic Generator → FIS
4. Luôn chạy E2E Test TRƯỚC, TRONG, và SAU mọi Chaos Drill
5. Verify X-Ray traces để confirm observability pipeline hoạt động

---

**Last Updated:** 2026-07-13  
**Author:** Principal SRE Mentor  
**Version:** 1.0