# ⚖️ AWS Architecture Trade-Offs & Decision Records

> **"There are no solutions. There are only trade-offs."** — Thomas Sowell
>
> Tài liệu này ghi lại các quyết định kiến trúc quan trọng (Architecture Decision Records - ADRs) khi thiết kế AWS Reliability Lab. Mỗi quyết định đều phân tích rõ **Context**, **Options**, **Decision**, và **Consequences** để người đọc hiểu được "WHY" đằng sau mỗi dòng code Terraform.

🔗 **Cross-Reference:** [README.md](../README.md) | [ARCHITECTURE.md](../ARCHITECTURE.md) | [On-Prem Architecture](../../on-premises/ARCHITECTURE.md)

---

## 📖 How to Use This Document

| Nếu bạn đang... | Đọc section... |
|-----------------|----------------|
| **Designing new infrastructure** | Toàn bộ để tránh "reinventing the wheel" |
| **Debugging production issue** | Section liên quan (VD: Network, Data) |
| **Preparing for System Design interview** | Focus vào Decision + Consequences |
| **Optimizing AWS bill** | Focus vào Cost-related trade-offs (TO-01, TO-03, TO-05) |

**Format:** Mỗi trade-off tuân theo chuẩn ADR (Architecture Decision Record):

- **Context** — Vấn đề cần giải quyết
- **Options** — Các lựa chọn đã cân nhắc
- **Decision** — Lựa chọn cuối cùng + lý do
- **Consequences** — Hệ quả (cả positive lẫn negative)
- **On-Prem Comparison** — So sánh với môi trường Docker Compose

---

## 🗂️ Trade-Off Index

| ID | Category | Trade-Off | Cost Impact | Learning Value |
|----|----------|-----------|-------------|----------------|
| [TO-01](#to-01-network-single-nat-vs-multi-az-nat) | Network | Single NAT vs Multi-AZ NAT | 💰💰💰 | ⭐⭐⭐⭐ |
| [TO-02](#to-02-data-managed-services-vs-self-hosted) | Data | Managed Services vs Self-Hosted | 💰💰💰💰 | ⭐⭐⭐⭐⭐ |
| [TO-03](#to-03-data-rds-proxy-vs-pgbouncer-on-ecs) | Data | RDS Proxy vs PgBouncer on ECS | 💰💰 | ⭐⭐⭐⭐⭐ |
| [TO-04](#to-04-compute-ecs-vs-eks) | Compute | ECS vs EKS | 💰 | ⭐⭐⭐⭐⭐ |
| [TO-05](#to-05-compute-fargate-vs-ec2) | Compute | Fargate vs EC2 Launch Type | 💰💰💰 | ⭐⭐⭐⭐ |
| [TO-06](#to-06-security-ssm-session-manager-vs-ssh-bastion) | Security | SSM Session Manager vs SSH Bastion | 💰 | ⭐⭐⭐ |
| [TO-07](#to-07-cicd-oidc-vs-long-lived-access-keys) | CI/CD | OIDC Federation vs Access Keys | — | ⭐⭐⭐⭐⭐ |
| [TO-08](#to-08-observability-self-hosted-vs-aws-managed) | Observability | Self-Hosted vs AWS Managed | 💰💰💰 | ⭐⭐⭐⭐⭐ |
| [TO-09](#to-09-dr-pilot-light-vs-active-active) | DR | Pilot Light vs Active-Active | 💰💰💰💰 | ⭐⭐⭐⭐ |
| [TO-10](#to-10-state-s3-backend-vs-terraform-cloud) | State | S3 Backend vs Terraform Cloud | 💰 | ⭐⭐⭐ |

---

## TO-01: Network — Single NAT vs Multi-AZ NAT

### 📋 Context

Các workload trong **Private Subnets** (ECS tasks, RDS, ElastiCache) cần outbound internet access để:

- Pull Docker images từ ECR
- Call AWS APIs (CloudWatch, Secrets Manager, SSM)
- Connect đến third-party APIs (Payment gateway, SMS)

NAT Gateway là cách duy nhất để private resources ra internet (không có public IP).

### 🎯 Options Considered

| Option | Cost ($/month) | Reliability | Complexity |
|--------|----------------|-------------|------------|
| **A. Single NAT** (1 AZ) | ~$32 | ❌ SPOF — AZ down = no outbound | Low |
| **B. Multi-AZ NAT** (1 per AZ) | ~$96 | ✅ HA — mỗi AZ tự chủ | Medium |
| **C. NAT Instances** (EC2) | ~$20 | ⚠️ Manual failover | High |
| **D. VPC Endpoints only** | ~$15 | ❌ Không ra được internet | Medium |

### ✅ Decision: Configurable (default = Single NAT cho Lab)

```hcl
variable "single_nat_gateway" {
  type        = bool
  default     = true   # Lab: save cost
  description = "Use single NAT (save $64/mo) or per-AZ NAT (production HA)"
}
```

### 💡 Consequences

**Positive:**

- Lab chạy 24/7 tốn ~$10/day thay vì ~$12/day
- Khi cần test HA → set `single_nat_gateway = false` và `terraform apply`

**Negative:**

- Nếu AZ-a sập, toàn bộ private subnet trong AZ-a mất outbound
- Acceptable risk vì Lab environment, không có real users

### 🔄 On-Prem Comparison

| Environment | Approach | Trade-Off |
|-------------|---------|-----------|
| On-Prem (Docker) | Single Docker bridge network | Không có khái niệm AZ, NAT |
| AWS (Lab) | Single NAT Gateway | Cost optimization |
| AWS (Production) | Multi-AZ NAT | High availability |

> **Learning:** Hiểu được Blast Radius của một single component trong Cloud vs On-Prem.

---

## TO-02: Data — Managed Services vs Self-Hosted

### 📋 Context

Hệ thống cần 3 data stores: PostgreSQL, Redis, Kafka. Có thể tự host chúng trên EC2/ECS (như On-Prem) hoặc dùng AWS Managed Services.

### 🎯 Options Considered

| Component | Option A: Self-Hosted | Option B: AWS Managed |
|-----------|----------------------|----------------------|
| PostgreSQL | EC2 + EBS + Docker | RDS Multi-AZ |
| Redis | EC2 + Docker | ElastiCache Replication Group |
| Kafka | EC2 + KRaft | MSK (Managed Streaming) |

### ✅ Decision: AWS Managed Services cho Data Layer

### 💡 Consequences

**Positive:**

- ✅ Auto failover: RDS Multi-AZ failover trong ~60s, ElastiCache < 30s
- ✅ Auto backup: Point-in-time recovery, automated snapshots
- ✅ Auto patching: Maintenance window tự động
- ✅ Focus vào app logic, không phải DBA work

**Negative:**

- ❌ Cost cao hơn 2-3x self-hosted
- ❌ Mất quyền kiểm soát: Không thể tune `postgresql.conf` tùy ý
- ❌ Vendor lock-in: Khó migrate sang cloud khác
- ❌ MSK cực kỳ đắt: ~$5/day cho 2 brokers t3.small

### 💰 Cost Breakdown (per month)

| Service | Self-Hosted | AWS Managed | Delta |
|---------|------------|-------------|-------|
| PostgreSQL | ~$30 (EC2 t3.medium) | ~$90 (RDS Multi-AZ) | +$60 |
| Redis | ~$15 (EC2 t3.small) | ~$45 (ElastiCache) | +$30 |
| Kafka | ~$60 (EC2 + EBS) | ~$150 (MSK 2 brokers) | +$90 |
| **Total** | **$105** | **$285** | **+$180** |

### 🔄 On-Prem Comparison

| Aspect | On-Prem (Docker) | AWS Managed |
|--------|-----------------|-------------|
| Setup time | 5 phút (docker-compose) | 30 phút (Terraform) |
| Failover | Manual (docker restart) | Automatic (~60s) |
| Backup | `pg_dump` cron job | Automated + PITR |
| Learning | PostgreSQL internals | AWS operations |

> **Learning:** Đánh đổi giữa Control và Operational Overhead. Production workload thường chọn Managed để giảm burden cho SRE team.

---

## TO-03: Data — RDS Proxy vs PgBouncer on ECS

### 📋 Context

Khi scale lên 10 services (EXPANSION_PLAN), chúng ta sẽ có:

- 10 services × 2 workers × 8 threads = 160 concurrent connections
- PostgreSQL default `max_connections = 100`
- Vượt ngưỡng → connection thrashing (CPU tăng, throughput giảm)

Cần một Connection Pooler đứng giữa App và Database.

### 🎯 Options Considered

| Option | Cost | Setup | Failover Transparency |
|--------|------|-------|-----------------------|
| A. RDS Proxy | $0.015/conn-hour | Terraform module | ✅ Yes |
| B. PgBouncer on ECS | Free (EC2 cost) | Docker image + config | ❌ No |
| C. PgBouncer on EC2 | Free (EC2 cost) | Manual setup | ❌ No |
| D. App-level pooling only | Free | Code change | ❌ No |

### ✅ Decision: RDS Proxy cho Production, PgBouncer reference cho learning

```hcl
# Module: rds-proxy (NEW)
resource "aws_db_proxy" "main" {
  name                   = "obs-rds-proxy"
  debug_logging          = false
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [var.rds_proxy_sg_id]
  vpc_subnet_ids         = var.data_subnet_ids

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = var.rds_secret_arn
    iam_auth    = "REQUIRED"
  }
}
```

### 💡 Consequences

**RDS Proxy (Production):**

- ✅ Failover transparent: App không cần reconnect khi RDS failover
- ✅ Connection multiplexing: 1000 app connections → 20 DB connections
- ✅ IAM authentication: Không cần password trong secrets
- ❌ Cost: ~$10/month cho 100 connections
- ❌ Chỉ hỗ trợ: PostgreSQL, MySQL, Aurora

**PgBouncer on ECS (Learning):**

- ✅ Free, học được cách configure pool mode
- ✅ Flexible: Session, Transaction, Statement modes
- ❌ Failover KHÔNG transparent: App phải reconnect
- ❌ Self-managed: Phải monitor, scale, patch

### 🔄 On-Prem Comparison

| Environment | Solution | Reason |
|-------------|---------|--------|
| On-Prem (EXPANSION_PLAN) | PgBouncer container | Không có RDS Proxy on-prem |
| AWS (Production) | RDS Proxy | AWS-native, seamless integration |

> **Learning:** Hiểu được Connection Multiplexing mechanism và tại sao Enterprise thường chọn Managed Proxy.

---

## TO-04: Compute — ECS vs EKS

### 📋 Context

Cần chọn Container Orchestration Platform để chạy 10 microservices. AWS có 2 options chính: ECS (Elastic Container Service) và EKS (Elastic Kubernetes Service).

### 🎯 Options Considered

| Aspect | ECS | EKS |
|--------|-----|-----|
| Learning curve | Thấp (AWS-native) | Cao (K8s ecosystem) |
| AWS integration | Tuyệt vời (CloudMap, ALB) | Tốt (qua controllers) |
| Portability | ❌ AWS-only | ✅ Multi-cloud |
| Ecosystem | Nhỏ | Khổng lồ (Helm, Istio, ArgoCD) |
| Cost | Free (chỉ trả compute) | $0.10/hr cluster fee + compute |

### ✅ Decision: Cả hai — qua 4 Compute Phases

```
Phase 8A: ECS on EC2       → Học EC2, ASG, Capacity Providers
Phase 8B: ECS on Fargate   → Học Serverless containers
Phase 8C: EKS + Node Group → Học K8s core, Helm, IRSA
Phase 8D: EKS + Fargate    → Học Fargate Profiles, mixed scheduling
```

### 💡 Consequences

**Positive:**

- ✅ Comparative learning: Trải nghiệm cả 2 platforms
- ✅ Real-world skills: Cả ECS và EKS đều có demand cao trên thị trường
- ✅ Decision-ready: Sau 4 phases, biết khi nào dùng cái gì

**Negative:**

- ❌ Effort x4: Phải viết 4 module Terraform
- ❌ Context switching: Mental model khác nhau giữa ECS và K8s

### 📊 Decision Matrix (khi nào dùng cái gì)

| Use Case | Recommendation | Why |
|----------|---------------|-----|
| AWS-only shop, simple apps | ECS | Đơn giản, AWS integration tốt |
| Multi-cloud, complex apps | EKS | Portability, ecosystem lớn |
| Có K8s expertise trong team | EKS | Tận dụng existing skills |
| Team mới, cần ship nhanh | ECS | Learning curve thấp |
| Cần advanced patterns (Istio, ArgoCD) | EKS | ECS không support |

### 🔄 On-Prem Comparison

| Environment | Orchestration | Learning |
|-------------|--------------|---------|
| On-Prem | Docker Compose | Declarative, simple |
| AWS Phase 8A/8B | ECS | AWS-native orchestration |
| AWS Phase 8C/8D | EKS | Industry standard K8s |

> **Learning:** Không có "best orchestration", chỉ có "right tool for the job".

---

## TO-05: Compute — Fargate vs EC2

### 📋 Context

Trong cả ECS và EKS, bạn phải chọn Launch Type: chạy trên EC2 instances bạn quản lý, hoặc Fargate (serverless).

### 🎯 Options Considered

| Aspect | EC2 Launch Type | Fargate |
|--------|----------------|---------|
| Management | Bạn (patching, scaling) | AWS |
| Billing | Per instance-hour | Per task-second |
| Cold start | Instant | ~30s |
| Storage | EBS (block) | EFS (file) only |
| Customization | Full (kernel, Docker daemon) | Limited |
| Cost at scale | Rẻ hơn | Đắt hơn |

### ✅ Decision: Fargate làm default, EC2 cho observability stack

```
Applications (10 services) → Fargate
├── Stateless
├── Scale-to-zero friendly
└── No persistent storage needed

Observability (Prometheus, Loki, Tempo) → EC2 (Node Group)
├── Stateful (cần EBS)
├── DaemonSets (host metrics)
└── Long-running, stable workload
```

### 💡 Consequences

**Positive:**

- ✅ Zero ops cho applications (không phải patch OS)
- ✅ Per-task billing — scale to 0 khi không có traffic
- ✅ 1:1 isolation — mỗi task chạy trên kernel riêng

**Negative:**

- ❌ EFS dependency — Observability trên Fargate phải dùng EFS ($)
- ❌ Cold start 30s — Không phù hợp latency-sensitive workloads
- ❌ Không có host-level access — Không thể chạy custom Docker daemon

### 🔄 On-Prem Comparison

| Environment | Equivalent | Note |
|-------------|-----------|------|
| On-Prem Docker | EC2 Launch Type | Bạn quản lý host |
| AWS Fargate | Không có tương đương | Serverless containers là cloud-native concept |

> **Learning:** Fargate đại diện cho Serverless 2.0 — abstraction cao hơn, ops thấp hơn, cost cao hơn.

---

## TO-06: Security — SSM Session Manager vs SSH Bastion

### 📋 Context

Cần một cách để debug private resources (RDS, ElastiCache, ECS tasks) từ bên ngoài VPC.

### 🎯 Options Considered

| Option | Security | Audit | Cost |
|--------|---------|-------|------|
| A. SSH Bastion (port 22) | ❌ Open port to internet | SSH logs only | Free |
| B. SSM Session Manager | ✅ No open ports | ✅ CloudTrail full audit | Free (< 1000 sessions) |
| C. VPN (AWS Client VPN) | ✅ Encrypted tunnel | ✅ Connection logs | $$/month |
| D. AWS Systems Manager Fleet Manager | ✅ GUI | ✅ | Free |

### ✅ Decision: SSM Session Manager + Bastion Host

```hcl
# Bastion instance with SSM agent pre-installed
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = var.mgmt_subnet_id
  vpc_security_group_ids = [var.bastion_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data = <<-EOF
    #!/bin/bash
    yum install -y postgresql16 redis kafka-python3
    # SSM agent already installed in Amazon Linux 2023
  EOF

  tags = {
    Name = "obs-bastion"
  }
}
```

### 💡 Consequences

**Positive:**

- ✅ Zero open ports — Không expose port 22 ra internet
- ✅ IAM-based access — Dùng IAM users/roles, không SSH keys
- ✅ Full audit trail — Mọi session được log trong CloudTrail
- ✅ Port forwarding — `aws ssm start-session --document-id AWS-StartPortForwardingSessionToRemoteHost`

**Negative:**

- ❌ SSM agent dependency — Instance phải có SSM agent
- ❌ Internet access required — Instance cần outbound internet để connect tới SSM service
- ❌ Learning curve — Không quen thuộc như `ssh user@host`

### 🔄 On-Prem Comparison

| Environment | Access Method | Note |
|-------------|-------------|------|
| On-Prem | SSH vào VM | Single point of access |
| AWS | SSM Session Manager | Cloud-native, audit-ready |

> **Learning:** Modern cloud security = no open ports + IAM everywhere + full audit.

---

## TO-07: CI/CD — OIDC vs Long-Lived Access Keys

### 📋 Context

GitHub Actions cần authenticate với AWS để push Docker images lên ECR và deploy ECS/EKS.

### 🎯 Options Considered

| Option | Security | Rotation | Complexity |
|--------|---------|---------|------------|
| A. IAM Access Keys (long-lived) | ❌ Leak risk | Manual (90 days) | Low |
| B. OIDC Federation | ✅ No secrets | Auto (1h tokens) | Medium |
| C. GitHub-hosted runner + VPN | ✅ | N/A | High |
| D. Self-hosted runner in VPC | ✅ | N/A | High |

### ✅ Decision: OIDC Federation (OpenID Connect)

```hcl
# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# IAM Role for deployment (trust policy scoped to repo + branch)
resource "aws_iam_role" "deploy" {
  name = "github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:dungtt/observability-lab:ref:refs/heads/main"
        }
      }
    }]
  })
}
```

### 💡 Consequences

**Positive:**

- ✅ No long-lived secrets — Không có Access Key để leak
- ✅ Scoped permissions — Chỉ repo + branch cụ thể mới assume role được
- ✅ Short-lived tokens — 1 hour expiry
- ✅ Audit trail — CloudTrail log mọi assume role

**Negative:**

- ❌ Setup complexity — Phải configure OIDC provider, trust policy
- ❌ GitHub dependency — Nếu GitHub OIDC service down, CI/CD block

### 🔄 On-Prem Comparison

| Environment | Authentication | Note |
|-------------|--------------|------|
| On-Prem | Không có CI/CD | Manual `docker compose up -d` |
| AWS | OIDC Federation | Zero-trust CI/CD |

> **Learning:** Zero-trust CI/CD là tiêu chuẩn mới của Enterprise. Never hardcode AWS credentials in GitHub Secrets.

---

## TO-08: Observability — Self-Hosted vs AWS Managed

### 📋 Context

Cần Metrics, Logs, Traces backends. Có thể tự host (Prometheus, Loki, Tempo) hoặc dùng AWS Managed (AMP, CloudWatch Logs, X-Ray).

### 🎯 Options Considered

| Signal | Self-Hosted | AWS Managed |
|--------|------------|-------------|
| Metrics | Prometheus | Amazon Managed Prometheus (AMP) |
| Logs | Loki | CloudWatch Logs |
| Traces | Tempo | X-Ray |
| Dashboards | Grafana | Amazon Managed Grafana (AMG) |

### ✅ Decision: Dual-Stack (cả hai)

```
Applications → OTel Collector → Self-Hosted (Prometheus/Loki/Tempo)
                             → AWS-native (CloudWatch/X-Ray)
```

### 💡 Consequences

**Positive:**

- ✅ Comparative learning — Hiểu pros/cons của mỗi approach
- ✅ Fallback — Nếu self-hosted down, vẫn có CloudWatch
- ✅ Best of both worlds — Custom dashboards trong Grafana, AWS-native alerts

**Negative:**

- ❌ Double storage cost — Data lưu ở 2 nơi
- ❌ Double engineering — Phải configure 2 pipelines

### 💰 Cost Comparison (per month, ~5K active series)

| Stack | Cost | Notes |
|-------|------|-------|
| Self-Hosted (EC2 + EBS) | ~$60 | 2× t3.medium + 100GB EBS |
| AWS Managed (AMP + CW) | ~$40 | Pay per metric + log ingestion |
| Dual-Stack | ~$100 | Cả hai |

### 🔄 On-Prem Comparison

| Environment | Stack | Reason |
|-------------|-------|--------|
| On-Prem | Self-Hosted only | Không có AWS Managed services |
| AWS | Dual-Stack | Learning opportunity |

> **Learning:** Managed services không phải lúc nào cũng tốt hơn. Self-hosted vẫn có chỗ đứng khi cần customization cao.

---

## TO-09: DR — Pilot Light vs Active-Active

### 📋 Context

Cần chiến lược Disaster Recovery khi primary region (ap-southeast-2) gặp sự cố lớn.

### 🎯 Options Considered

| Strategy | RTO | RPO | Cost | Complexity |
|----------|-----|-----|------|------------|
| Backup & Restore | Hours | 24h | 💰 | Low |
| Pilot Light | 10-15 min | Minutes | 💰💰 | Medium |
| Warm Standby | Minutes | Seconds | 💰💰💰 | High |
| Active-Active | ~0 | ~0 | 💰💰💰💰 | Very High |

### ✅ Decision: Pilot Light (Tier 2)

```
Primary Region (ap-southeast-2):
├── Full production workload
└── Daily cross-region backup → DR region

DR Region (ap-southeast-1):
├── VPC (pre-provisioned)
├── RDS Read Replica (async)
├── Empty ECS/EKS cluster
└── Route53 failover routing
```

### 💡 Consequences

**Positive:**

- ✅ RTO ~15 phút — Acceptable cho Lab
- ✅ Cost thấp — Chỉ trả cho RDS replica + VPC (~$20/month)
- ✅ DR drill được — Có thể test promotion định kỳ

**Negative:**

- ❌ RPO = Minutes — Mất dữ liệu gần nhất (acceptable cho Lab)
- ❌ Manual failover — Cần runbook để promote

### 🔄 On-Prem Comparison

| Environment | DR Strategy | RTO | RPO |
|-------------|------------|-----|-----|
| On-Prem | Backup & Restore (`pg_dump`) | 30 min | 24h |
| AWS | Pilot Light | 15 min | Minutes |

> **Learning:** DR strategy phải match với business requirements. Không cần Active-Active cho Lab, nhưng phải biết cách implement nó.

---

## TO-10: State — S3 Backend vs Terraform Cloud

### 📋 Context

Terraform state cần được lưu trữ an toàn, có locking, và share được giữa team.

### 🎯 Options Considered

| Option | Cost | Locking | Team Collaboration |
|--------|------|---------|-------------------|
| A. Local state | Free | ❌ | ❌ |
| B. S3 + DynamoDB | ~$1/month | ✅ | ✅ (manual) |
| C. Terraform Cloud | Free (5 users) | ✅ | ✅ (UI/UX tốt) |
| D. Terraform Enterprise | $$ | ✅ | ✅ (SSO, policy) |

### ✅ Decision: S3 + DynamoDB (native lockfile)

```hcl
terraform {
  backend "s3" {
    bucket       = "obs-terraform-state-2026"
    key          = "shared/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    kms_key_id   = "alias/terraform-state"
    use_lockfile = true  # Native locking (Terraform 1.10+)
  }
}
```

### 💡 Consequences

**Positive:**

- ✅ Full control — State nằm trong AWS account của bạn
- ✅ KMS encryption — State được encrypt at-rest
- ✅ Native locking — Không cần DynamoDB nữa (Terraform 1.10+)
- ✅ Cost ~$1/month — Rất rẻ

**Negative:**

- ❌ No UI — Phải dùng `terraform state list`, `terraform state show`
- ❌ Manual team setup — Phải cấp IAM permissions cho team members

### 🔄 On-Prem Comparison

| Environment | State Management | Note |
|-------------|----------------|------|
| On-Prem | N/A (Docker Compose) | Không có IaC state |
| AWS | S3 Backend | Industry standard |

> **Learning:** State management là trái tim của IaC. Mất state = mất infrastructure.

---
## TO-11: Observability — Dual-Stack Telemetry Routing (Logs vs Metrics/Traces)

### 📋 Context
Khi đưa ECS Fargate lên AWS, chúng ta cần thu thập 3 trụ cột Observability: Metrics, Traces, và Logs. 
Vấn đề đặt ra: Liệu có nên "All-in" mọi thứ vào ADOT (AWS Distro for OpenTelemetry) Sidecar và đẩy về các backend Open-source tự host (hoặc managed) giống hệt môi trường On-Premises, hay nên tận dụng các AWS Native Services?

Môi trường On-Premises hiện tại đang dùng: `App -> OTel Collector -> Prometheus (Metrics) + Tempo (Traces) + Loki (Logs)`. Tất cả hội tụ về một Grafana duy nhất.

### 🎯 Options Considered

| Option | Architecture | Storage Admin Effort | Cost | Context Switching |
|---|---|---|---|---|
| **A. All-in OTel (On-Prem style)** | App -> ADOT Sidecar -> AMP (Metrics), X-Ray (Traces), **Self-hosted Loki on EFS/ECS** (Logs) | 🔴 High (Phải quản lý EFS, scale Loki, index shards) | 💰💰💰 (EFS cost + ECS compute cho Loki) | 🟢 Low (1 UI: Grafana) |
| **B. AWS Native All-in** | App -> CloudWatch Agent -> CloudWatch Metrics, CloudWatch Logs, X-Ray | 🟢 Zero | 💰💰 (CW Logs ingestion cost) | 🟡 Medium (CW UI is clunky for traces) |
| **C. Dual-Stack / Hybrid (Selected)** | App -> ADOT Sidecar (Metrics -> AMP, Traces -> X-Ray). <br> App -> `awslogs` driver (Logs -> CloudWatch Logs) | 🟢 Zero | 💰 (Optimized: AMP/X-Ray for deep debug, CW for cheap log storage) | 🔴 High (Must switch between X-Ray, AMP, CW Logs Insights) |

### ✅ Decision: Option C — Dual-Stack Telemetry Routing
Chúng ta chấp nhận việc "lệch pha" so với On-Premises:
1. **Metrics & Traces:** Dùng ADOT Sidecar đẩy về Amazon Managed Prometheus (AMP) và AWS X-Ray. (Giữ nguyên triết lý OTel-Native Bridge, vendor-neutral ở tầng App).
2. **Logs:** Bỏ qua OTel cho Logs. Dùng `awslogs` driver native của ECS Fargate đẩy thẳng stdout/stderr lên CloudWatch Logs.

### 💡 Consequences

**Positive:**
- ✅ **Zero Storage Admin cho Logs:** Không phải đau đầu setup Loki, không lo EFS bị đầy, không lo Loki index bị corrupt. CloudWatch Logs tự động scale, nén và archive.
- ✅ **Tiết kiệm CPU/RAM cho Fargate:** `awslogs` driver chạy ở tầng ECS Agent (infra), không tốn tài nguyên của Task (vốn đã bị chia sẻ cho ADOT Sidecar).
- ✅ **Log Insights cực mạnh:** CloudWatch Logs Insights cho phép query JSON log bằng ngôn ngữ gần giống SQL, cực kỳ phù hợp để filter `trace_id` hoặc `order_id` mà không cần build custom index.
- ✅ **Chi phí tối ưu:** Lưu Logs trên CW rẻ hơn nhiều so với việc trả tiền compute cho Loki self-hosted trên ECS.

**Negative:**
- ❌ **UI Context Switching (Điểm đau nhất):** Khi debug một request, SRE phải:
  1. Vào X-Ray để xem Trace flow (ALB -> Order -> Payment).
  2. Copy `trace_id` từ X-Ray.
  3. Switch sang CloudWatch Logs Insights, paste `trace_id` vào query để tìm log chi tiết.
  4. Switch sang AMG (Grafana) để xem metric CPU/DB.
- ❌ **Mất đi "Single Pane of Glass":** Không có một dashboard duy nhất hiển thị cả 3 pillars như Grafana on-prem.

**Mitigation (Cách giảm thiểu):**
- Thiết lập **Grafana (AMG)** làm Central Dashboard. Dùng CloudWatch Data Source trong Grafana để query Logs, AMP Data Source để query Metrics. (Dù X-Ray trace vẫn phải xem ở AWS Console, nhưng Logs + Metrics đã hội tụ).
- Enforce **Structured Logging (JSON)** ở tầng App code. Bắt buộc mọi log phải có `trace_id`, `span_id`, `order_id`. Điều này giúp CloudWatch Logs Insights query cực nhanh.

### 🔄 On-Prem Comparison

| Environment | Telemetry Flow | Rationale |
|---|---|---|
| **On-Premises** | `OTel Collector -> Loki/Tempo/Prometheus -> Grafana` | Tự do vọc vạch, không tốn tiền cloud, học sâu về storage backend. |
| **AWS (Lab/Prod)** | `ADOT -> AMP/X-Ray` + `awslogs -> CW Logs` | Tập trung 100% thời gian vào việc viết PromQL, TraceQL, Alerting Rules thay vì làm "Storage Admin" cho Loki/Tempo. |

**Learning Value:** Hiểu được ranh giới giữa "Instrumentation" (OTel SDK) và "Storage/Backend" (AWS Managed). App code hoàn toàn "mù" về hạ tầng, nhưng Platform Engineer phải biết chọn backend nào tối ưu chi phí và vận hành cho Cloud-Native.
---

## 🎯 Summary: The "Golden Rules" of AWS Architecture

Sau 10 trade-offs, đây là 5 nguyên tắc vàng rút ra được:

**1. Pay for What You Use 💰**

Fargate, RDS Proxy, NAT Gateway — tất cả đều billing per-second/per-hour. Destroy khi không dùng.

**2. Managed Services > Self-Hosted (usually) 🛠️**

Trừ khi có lý do đặc biệt (cost, customization), hãy chọn Managed Services để giảm operational burden.

**3. Security by Default 🔒**

- No open ports (SSM Session Manager)
- No long-lived credentials (OIDC)
- Encryption everywhere (KMS CMK)
- Least privilege IAM

**4. Multi-AZ for Stateful, Single-AZ for Stateless 🏗️**

- RDS, ElastiCache, MSK → Multi-AZ
- ECS tasks, Lambda → Single-AZ (scale horizontally)

**5. Document the "Why", Not Just the "What" 📖**

Code có thể thay đổi, nhưng reasoning đằng sau decisions mới là thứ giúp team scale.

---

## 🔄 Continuous Review

Tài liệu này **KHÔNG** phải là static. Review và update khi:

- ✅ Thêm service mới (VD: OpenSearch → TO-02 cần update)
- ✅ AWS ra service mới (VD: MSK Express → cheaper option)
- ✅ Cost optimization opportunities
- ✅ Post-mortem từ incident

**Next Review Date:** 2026-09-01 (quarterly)

---

## 📚 Further Reading

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/)
- Google SRE Book — Managing Critical State
- Terraform ADR Template

---

> 🛡️ *"Architecture is the art of making decisions that are expensive to change. Make them wisely, document them thoroughly."*