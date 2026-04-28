# Phase 8: AWS Infrastructure — Production-Grade Deployment Plan

## Mục tiêu

Deploy hệ thống observability lab lên AWS bằng Terraform theo **production-grade standards**. Shared infrastructure deploy 1 lần, sau đó swap giữa các compute platforms (ECS / EKS) để học và so sánh.

---

## Kiến trúc tổng quan

```
┌────────────────────────────────────────────────────────────────────┐
│                    SHARED INFRASTRUCTURE                           │
│                                                                    │
│  Layer 1 — Foundation                                              │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │ Network  │→ │ VPC Endpoints│→ │   Security   │                │
│  │ (VPC)    │  │ (S3/DDB/ECR) │  │ (SG/IAM)     │                │
│  └──────────┘  └──────────────┘  └──────────────┘                │
│                                                                    │
│  Layer 2 — Data                                                    │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │ Database │  │    Cache     │  │  Streaming   │                │
│  │ (RDS PG) │  │ (ElastiCache)│  │  (MSK Kafka) │                │
│  └──────────┘  └──────────────┘  └──────────────┘                │
│                                                                    │
│  Layer 3 — Platform Services                                       │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │   ECR    │  │     EFS      │  │  Loadbalancer│                │
│  │ (Images) │  │ (Persistent) │  │ (ALB/ACM/R53)│                │
│  └──────────┘  └──────────────┘  └──────────────┘                │
│                                                                    │
│  Layer 4 — Operations                                              │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Bastion  │  │   CI/CD      │  │   Backup     │  │ Budgets  │ │
│  │ (SSM)    │  │ (OIDC+GHA)   │  │ (AWS Backup) │  │ (Cost)   │ │
│  └──────────┘  └──────────────┘  └──────────────┘  └──────────┘ │
├────────────────────────────────────────────────────────────────────┤
│                    COMPUTE LAYER (swap)                             │
│                                                                    │
│  Phase 8A: ECS on EC2        │  Phase 8B: ECS on Fargate          │
│  Phase 8C: EKS + Node Group  │  Phase 8D: EKS + Fargate Profile   │
├────────────────────────────────────────────────────────────────────┤
│                    OBSERVABILITY (dual-stack)                       │
│                                                                    │
│  Self-hosted: Prometheus, Grafana, Loki, Tempo, OTel               │
│  AWS-native:  CloudWatch, Container Insights, X-Ray                │
└────────────────────────────────────────────────────────────────────┘
```

---

## Quyết định đã confirm ✅

| Quyết định | Giá trị |
|-----------|---------| 
| Region | `ap-southeast-2` (Sydney) |
| State Backend | S3 + DynamoDB (KMS encrypted, state locking) |
| Cross-state sharing | `terraform_remote_state` data source |
| Data services | AWS Managed: RDS, ElastiCache, MSK |
| Container registry | **Dual: ECR + GHCR** (CI push cả hai) |
| CI/CD auth | OIDC → IAM Role (không dùng Access Key) |
| NAT Gateway | Standard NAT (single = save cost, multi = HA) |
| Bastion | EC2 + SSM Session Manager |
| Observability | Dual: Grafana stack (self-hosted) + CloudWatch |
| Backup | AWS Backup (centralized, cross-service) |
| DR Strategy | Tier 2 — Pilot Light (cross-region backup + RDS replica) |
| DR Region | `ap-southeast-1` (Singapore) |

---

## Shared Modules — Chi Tiết

### Tiến độ tổng quan

| # | Module | Trạng thái | Mô tả |
|---|--------|-----------|-------|
| 1 | `network` | ✅ Done | VPC, Subnets (4-tier × 3 AZs), NAT, NACLs, Flow Logs |
| 2 | `vpc-endpoints` | ✅ Done | S3/DynamoDB Gateway + Interface Endpoints |
| 3 | `security` | ✅ Done | 6 SGs, ECS IAM Roles, Key Pair |
| 4 | `database` | ✅ Done | RDS PostgreSQL, KMS, Secrets Manager, Monitoring |
| 5 | `cache` | 🔲 TODO | ElastiCache Redis |
| 6 | `streaming` | 🔲 TODO | MSK Kafka |
| 7 | `ecr` | 🔲 TODO | Container Registry (7 repos) |
| 8 | `efs` | 🔲 TODO | Elastic File System |
| 9 | `loadbalancer` | 🔲 TODO | ALB + ACM + Route53 |
| 10 | `bastion` | 🔲 TODO | EC2 Jump Host + SSM |
| 11 | `cicd` | 🔲 TODO | OIDC Provider + GitHub Actions IAM |
| 12 | `backup` | 🔲 TODO | AWS Backup + Cross-Region Copy (DR Tier 1) |
| 13 | `budgets` | 🔲 TODO | AWS Budgets + Cost Anomaly Detection |
| 14 | `dr` | 🔲 TODO | Pilot Light DR (RDS replica + infra ở DR region) |

---

### Module 1: `network` ✅

| Resource | Config |
|----------|--------|
| VPC | 10.0.0.0/16 |
| Public Subnets × 3 | 10.0.1-3.0/24 — ALB, NAT, Bastion |
| Private Subnets × 3 | 10.0.11-13.0/24 — Compute workloads |
| Data Subnets × 3 | 10.0.21-23.0/24 — RDS, Redis, MSK, EFS |
| Mgmt Subnets × 3 | 10.0.31-33.0/24 — Bastion, admin tools |
| NAT Gateway | Configurable: 1 (save cost) or 3 (HA, per-AZ) |
| NACLs | Stateless deny rules per tier |
| VPC Flow Logs | CloudWatch (30-day retention) |

---

### Module 2: `vpc-endpoints` ✅

| Type | Endpoints | Cost |
|------|-----------|------|
| Gateway (FREE) | S3, DynamoDB | $0 |
| Interface | ECR (api + dkr), SSM, Secrets Manager, Logs, STS | ~$7.2/month/endpoint/AZ |

---

### Module 3: `security` ✅

**Security Groups (Defense-in-Depth):**

| SG | Inbound | Outbound |
|----|---------|----------|
| ALB | 80/443 from Internet | app_port to App SG |
| Application | app_port from ALB, SSH from Bastion | Data ports, EFS, HTTPS, OTLP to Obs |
| Data | DB ports from App + Bastion | Ephemeral responses only |
| EFS | NFS (2049) from App | Ephemeral responses |
| Observability | OTLP 4317/4318 from App, monitoring ports from VPC | HTTPS, scrape ports |
| Bastion | SSH from trusted CIDRs | SSH/DB ports/HTTPS/DNS |

**IAM Roles:**

| Role | Permissions |
|------|-------------|
| ECS Task Execution | ECR pull, CloudWatch Logs, SSM/Secrets read, KMS decrypt |
| ECS Task | CloudWatch metrics, X-Ray traces, ECS Exec (SSM) |
| Bastion | SSM managed instance |

---

### Module 4: `database` ✅

| Resource | Config |
|----------|--------|
| RDS PostgreSQL 16 | db.t3.micro, gp3, encrypted (CMK) |
| Secrets Manager | RDS-managed auto-rotation (7 days) |
| SSM Parameters | endpoint, host, port, db_name, username, secret_arn |
| CloudWatch Alarms | CPU, storage, connections, secret rotation failure |
| Performance Insights | Enabled (7d free, 731d prod) |
| Read Replicas | Configurable count (0 for lab) |
| KMS | Dedicated CMK for RDS + Secrets |
| Enhanced Monitoring | Configurable interval |

---

### Module 5: `cache` 🔲

Replaces **Docker Redis** from on-premises.

| Resource | Config |
|----------|--------|
| ElastiCache Replication Group | Redis 7.x, cache.t3.micro |
| Subnet Group | Data subnets |
| Parameter Group | Custom Redis tuning (maxmemory-policy, timeout) |
| KMS Key | Encryption at-rest (CMK) |
| Auth Token | Secrets Manager + auto-rotation |
| SSM Parameters | Primary endpoint, reader endpoint, port |
| CloudWatch Alarms | CPU, memory, connections, replication lag |
| Slow Log | CloudWatch Log Group |

**Production features:** encryption in-transit (TLS), automatic failover, Multi-AZ option.

---

### Module 6: `streaming` 🔲

Replaces **Docker Kafka (KRaft)** from on-premises.

| Resource | Config |
|----------|--------|
| MSK Cluster | kafka.t3.small, 2 brokers (lab) / 3 (prod) |
| MSK Configuration | Custom broker config (auto.create.topics, retention) |
| KMS Key | Encryption at-rest (CMK) |
| CloudWatch Log Group | Broker logs |
| SSM Parameters | Bootstrap brokers (TLS), ZooKeeper connect |
| CloudWatch Alarms | Under-replicated partitions, offline partitions, disk usage |

**Production features:** TLS encryption, IAM auth, Multi-AZ, S3 log delivery.

> [!WARNING]
> MSK là resource **tốn chi phí nhất** (~$5/ngày với 2 brokers t3.small). Nên destroy khi không dùng.

---

### Module 7: `ecr` 🔲

| Resource | Config |
|----------|--------|
| ECR Repositories × 7 | api-gateway, order-service, payment-service, notification-worker, inventory-worker, traffic-gen, web-ui |
| Lifecycle Policy | Keep last 10 tagged images, expire untagged after 7 days |
| Image Scanning | Scan on push (basic) |
| Encryption | KMS (CMK) hoặc AES-256 default |
| Repository Policy | Allow pull from ECS/EKS task roles |

---

### Module 8: `efs` 🔲

Persistent storage cho observability stack (Phase 8B/8D Fargate cần EFS vì không có EBS).

| Resource | Config |
|----------|--------|
| EFS File System | Encrypted (CMK), Bursting throughput |
| Access Points × 4 | prometheus-data, loki-data, tempo-data, grafana-data |
| Mount Targets × 3 | 1 per private subnet |
| Backup Policy | Enabled (integrated với AWS Backup) |
| Lifecycle Policy | Transition to IA after 30 days |

---

### Module 9: `loadbalancer` 🔲

Entry point cho tất cả traffic vào ứng dụng.

| Resource | Config |
|----------|--------|
| ALB | Internet-facing, public subnets |
| Target Groups | web-ui (:8580), api-gateway (:5000), grafana (:3000) |
| Listener Rules | Host-based routing: app.*, api.*, grafana.* |
| ACM Certificate | `*.bd-apa-coi.com` (DNS validation) |
| Route53 Records | A records → ALB alias |
| WAF v2 (optional) | AWS Managed Rules: CommonRuleSet, SQLi, XSS, rate limiting |
| Access Logs | S3 bucket |

---

### Module 10: `bastion` 🔲

| Resource | Config |
|----------|--------|
| EC2 Instance | t3.micro, Amazon Linux 2023, mgmt subnet |
| SSM Agent | Pre-installed, no SSH key needed cho SSM access |
| User Data | Install PostgreSQL client, Redis CLI, Kafka tools |
| Instance Profile | Bastion IAM role (from security module) |
| Security Group | Bastion SG (from security module) |
| CloudWatch Agent | System metrics + memory/disk |

> [!TIP]
> Bastion + SSM Session Manager = SSH access **without** opening port 22 from Internet. Secure by default.

---

### Module 11: `cicd` 🔲

GitHub Actions → AWS authentication **without Access Keys**.

| Resource | Config |
|----------|--------|
| OIDC Provider | Trust `token.actions.githubusercontent.com` |
| IAM Role: `ecr-push` | Push images to ECR |
| IAM Role: `deploy` | Update ECS services / kubectl apply |
| Trust Policy | Scoped to repo + branch (main only) |

```
GitHub Actions Workflow
    ↓ (OIDC JWT Token)
AWS STS verify
    ↓ (check repo, branch)
Assume IAM Role
    ↓ (temp credentials, 1h)
Push ECR / Deploy ECS/EKS
```

---

### Module 12: `backup` 🔲

> [!IMPORTANT]
> Bắt buộc cho production-grade. Centralized backup management + cross-region copy (DR Tier 1 foundation).

| Resource | Config |
|----------|--------|
| Backup Vault (primary) | KMS encrypted, access policy, vault lock (governance) |
| Backup Vault (DR region) | Cross-region copy destination (`ap-southeast-1`) |
| Backup Plan — Daily | Daily 3AM UTC, retention 35 days |
| Backup Plan — Monthly | 1st of month, retention 365 days, cold storage after 30d |
| Backup Selection | Tag-based: `Backup = true` (auto-discover new resources) |
| Cross-Region Copy | Daily backup → DR region vault |
| IAM Role | AWS Backup service role |
| Vault Lock | Governance mode (admin can override for lab) |
| SNS Topic + Subscription | Alert on backup/copy failures |
| CloudWatch Alarm | Backup job failure detection |

**Backup schedule:**

| Resource | RPO | Retention | Cross-Region |
|----------|-----|-----------|-------------|
| RDS | Daily + PITR (seconds) | 35 days daily / 365 days monthly | ✅ Daily copy to DR |
| EFS | Daily | 35 days daily / 365 days monthly | ✅ Daily copy to DR |

---

### Module 13: `budgets` 🔲

> [!IMPORTANT]
> Module này cũng **không có trong plan cũ**. Bắt buộc để tránh chi phí bất ngờ khi chạy lab.

| Resource | Config |
|----------|--------|
| AWS Budget | Monthly cost budget ($50/month cho lab) |
| Budget Alert | 80% threshold → email notification |
| Cost Anomaly Monitor | Detect unusual spending patterns |
| SNS Topic | Shared topic cho budget + backup alerts |

---

### Module 14: `dr` 🔲

> [!NOTE]
> DR Pilot Light module — triển khai **sau khi app chạy ổn ở primary region**. Tách riêng vì DR infra có lifecycle khác (ít thay đổi, cần stability).

**Học được:** Cross-region architecture, RDS promotion, DNS failover, DR drill.

| Resource | Config |
|----------|--------|
| VPC (DR region) | Mirror primary VPC topology (`ap-southeast-1`) |
| Subnets (DR region) | Public/Private/Data × 2 AZs (minimum cho DR) |
| RDS Cross-Region Read Replica | Async replication từ primary |
| ALB (DR region) | Pre-provisioned, empty target groups |
| Route53 Failover Routing | Primary → active, DR → standby |
| Route53 Health Check | Monitor primary ALB endpoint |

**DR Drill procedure:**
```
1. Promote RDS replica → standalone primary       (~5 min)
2. Scale compute from 0 → desired count            (~3-5 min)
3. Verify app health in DR region                   (~2 min)
4. Switch Route53 DNS → DR ALB (or auto-failover)  (~60s TTL)
Total RTO: ~10-15 minutes
```

---

## Compute Phases

> [!NOTE]
> Mỗi compute phase là **một module riêng**, deploy độc lập trên shared infrastructure. Chỉ chạy 1 phase tại một thời điểm, destroy trước khi chuyển sang phase tiếp.

### Phase 8A: ECS on EC2

**Học được:** EC2 management, ECS scheduling, capacity provider, ASG.

| Resource | Config |
|----------|--------|
| ECS Cluster | EC2 capacity provider |
| ASG | t3.medium, min=2 max=4, ECS-optimized AMI |
| Capacity Provider | Managed scaling, target 80% utilization |
| Task Definitions × 7 | 1 per service, `awslogs` log driver |
| ECS Services × 7 | Desired count, health check, deployment circuit breaker |
| Service Discovery | AWS Cloud Map (private DNS namespace) |
| Observability Tasks | ECS tasks on same cluster (EBS volumes) |

### Phase 8B: ECS on Fargate

**Học được:** Serverless containers, `awsvpc` networking, EFS integration.

| Resource | Config |
|----------|--------|
| ECS Cluster | Fargate capacity provider |
| Task Definitions × 7 | Fargate-compatible, `awsvpc` mode |
| Auto Scaling | Target tracking (CPU/Memory) |
| Platform Version | LATEST (1.4.0+) |
| EFS Volumes | Observability persistent data |

**So sánh với 8A:**

| | 8A (EC2) | 8B (Fargate) |
|---|---|---|
| EC2 quản lý | Bạn | AWS |
| Cold start | Instant | ~30s |
| Cost model | Per instance | Per task |
| Storage | EBS | EFS |

### Phase 8C: EKS + Managed Node Group

**Học được:** K8s core (Deployments, Services, Ingress, Helm), IRSA.

| Resource | Config |
|----------|--------|
| EKS Cluster | Managed control plane v1.29+ |
| Managed Node Group | t3.medium, min=2 max=4 |
| K8s Manifests | Deployments, Services, ConfigMaps, Secrets, Ingress |
| IRSA | Pod-level IAM roles |
| AWS LB Controller | Ingress → ALB integration |
| Cluster Autoscaler | Scale nodes based on pending pods |
| Observability | DaemonSets + StatefulSets (EBS PVCs) |

### Phase 8D: EKS + Fargate Profile

**Học được:** Fargate Profile selectors, mixed scheduling (apps on Fargate, observability on EC2).

| Resource | Config |
|----------|--------|
| EKS Cluster | Reuse từ 8C |
| Fargate Profile | namespace: applications |
| Node Group | Keep cho observability (DaemonSet, EBS) |
| CoreDNS | Patched for Fargate |

---

## Dual-stack Observability per Phase

| Signal | Self-hosted | AWS-native |
|--------|------------|------------|
| App metrics | Prometheus (OTel) | CloudWatch Metrics |
| App logs | Loki (structured JSON) | CloudWatch Logs |
| Traces | Tempo (OTel) | X-Ray (optional) |
| Dashboards | Grafana | CloudWatch Dashboards |
| Infra metrics | Node Exporter | CloudWatch + Container Insights |
| DB performance | — | RDS Performance Insights |
| Alerting | Alertmanager → Telegram | CloudWatch Alarms → SNS |

---

## Directory Structure

```
terraform/
├── README.md                     ← Overview + quick start
├── IMPLEMENTATION_PLAN.md        ← Tài liệu này (chi tiết modules)
├── ARCHITECTURE.md               ← Sơ đồ Mermaid kiến trúc AWS
│
├── bootstrap/                    # S3 + DynamoDB state backend
│
├── modules/                      # Reusable modules
│   ├── network/              ✅  # VPC, Subnets, NAT, NACLs, Flow Logs
│   ├── vpc-endpoints/        ✅  # S3/DDB Gateway + Interface Endpoints
│   ├── security/             ✅  # SGs, IAM, Key Pair
│   ├── database/             ✅  # RDS PostgreSQL + Secrets + Monitoring
│   ├── cache/                🔲  # ElastiCache Redis
│   ├── streaming/            🔲  # MSK Kafka
│   ├── ecr/                  🔲  # Container Registry
│   ├── efs/                  🔲  # Elastic File System
│   ├── loadbalancer/         🔲  # ALB + ACM + Route53 + WAF
│   ├── bastion/              🔲  # EC2 Jump Host + SSM
│   ├── cicd/                 🔲  # OIDC + GitHub Actions IAM
│   ├── backup/               🔲  # AWS Backup + cross-region copy
│   ├── budgets/              🔲  # AWS Budgets + Cost Anomaly
│   ├── dr/                   🔲  # Pilot Light DR (VPC + RDS replica)
│   ├── ecs-ec2/              🔲  # Phase 8A compute
│   ├── ecs-fargate/          🔲  # Phase 8B compute
│   ├── eks-nodegroup/        🔲  # Phase 8C compute
│   └── eks-fargate/          🔲  # Phase 8D compute
│
├── environments/
│   ├── shared/               ✅  # All shared modules wired here
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── backend.tf           # S3 backend (active)
│   ├── dev/                      # Terraform Cloud backend (testing)
│   ├── phase-8a/             🔲  # ECS on EC2
│   ├── phase-8b/             🔲  # ECS on Fargate + EFS
│   ├── phase-8c/             🔲  # EKS + Node Group
│   └── phase-8d/             🔲  # EKS + Fargate Profile
│
└── policy/                   ✅  # OPA/Rego policy-as-code + tests
    ├── general.rego
    ├── network.rego
    ├── rds.rego
    ├── security_group.rego
    ├── iam.rego
    ├── kms.rego
    ├── s3.rego
    ├── secrets.rego
    ├── logging.rego
    ├── vpc_endpoint.rego
    └── tests/
```

---

## Thứ tự triển khai (Dependency-based)

### Step 1: Protect existing infrastructure

```
backup (bảo vệ RDS đang chạy)
```

Lý do: **"Protect what you have before building more."** RDS đã live, cần backup centralized + cross-region copy trước.

### Step 2: Hoàn tất Shared Data Layer

```
cache → streaming
```

Lý do: apps depend on Redis + Kafka.

### Step 3: Platform Services

```
ecr → efs → loadbalancer
```

Lý do: ECR cần trước khi push images. EFS cần cho Fargate observability. ALB cần cho traffic routing.

### Step 4: Operations

```
bastion → cicd → budgets
```

Lý do: bastion cho admin access. CICD cho automated deployment. Budgets cho cost monitoring.

### Step 5: First Compute Phase

```
phase-8a (ECS on EC2) → deploy apps → test → compare
```

### Step 6: Subsequent Compute Phases

```
phase-8b → phase-8c → phase-8d (mỗi phase: deploy → learn → compare → destroy)
```

### Step 7: Disaster Recovery (sau khi app chạy ổn)

```
dr (Pilot Light — VPC + RDS replica ở ap-southeast-1) → DR drill test
```

---

## Estimated Cost (when running)

| Resource | $/hr | $/day |
|----------|------|-------|
| NAT Gateway (×1) | $0.045 | $1.08 |
| MSK (2 brokers t3.small) | $0.21 | $5.04 |
| RDS (t3.micro) | $0.018 | $0.43 |
| ElastiCache (t3.micro) | $0.017 | $0.41 |
| ALB | $0.023 | $0.54 |
| ECS/EC2 (2× t3.medium) | $0.084 | $2.02 |
| EFS | ~$0.01 | ~$0.24 |
| Bastion (t3.micro) | $0.01 | $0.25 |
| **Total shared + 1 phase** | **~$0.42** | **~$10** |

> [!TIP]
> `terraform destroy` → **$0/day**. Apply sáng, destroy tối ≈ $10/ngày.
> NAT Gateway + MSK chiếm ~60% chi phí. Cân nhắc `single_nat_gateway = true` cho lab.

---

## OPA Policy Coverage

| Policy File | Validates |
|-------------|-----------|
| `general.rego` | Tagging, description requirements |
| `network.rego` | Subnet CIDR, public access restrictions |
| `rds.rego` | Encryption, backup, multi-AZ, public access |
| `security_group.rego` | Port ranges, CIDR validation, no 0.0.0.0/0 on data tier |
| `iam.rego` | No wildcard permissions, trust policy constraints |
| `kms.rego` | Key rotation, deletion window |
| `s3.rego` | Encryption, versioning, public access block |
| `secrets.rego` | Encryption, recovery window |
| `logging.rego` | Retention, encryption |
| `vpc_endpoint.rego` | Policy validation |

> [!NOTE]
> Cần thêm policies cho: `elasticache.rego`, `msk.rego`, `efs.rego`, `alb.rego`, `backup.rego` khi modules tương ứng được triển khai.
