# Phase 8: AWS Infrastructure — Multi-Platform Learning Path (FINAL)

## Mục tiêu

Deploy hệ thống observability lab lên AWS bằng Terraform, **so sánh 4 compute platforms** trên cùng shared infrastructure.

---

## Kiến trúc tổng quan

```
┌────────────────────────────────────────────────────────────┐
│  SHARED INFRASTRUCTURE (deploy 1 lần, dùng chung)         │
│                                                            │
│  Network → Security → Data → ALB → Secrets → ECR → EFS   │
│  (VPC)    (SG/IAM)   (RDS,   (Route53) (SSM)    (NFS)    │
│                      ElastiCache,                          │
│                      MSK)                                  │
│           Bastion → CI/CD                                  │
│           (SSH/SSM)  (OIDC + GitHub Actions IAM Role)      │
├────────────────────────────────────────────────────────────┤
│  COMPUTE LAYER (swap giữa 4 phases)                       │
│                                                            │
│  8A: ECS on EC2          8B: ECS on Fargate               │
│  8C: EKS + Node Group    8D: EKS + Fargate Profile        │
├────────────────────────────────────────────────────────────┤
│  OBSERVABILITY (dual-stack)                                │
│                                                            │
│  Self-hosted: Prometheus, Grafana, Loki, Tempo, OTel      │
│  AWS-native:  CloudWatch, Container Insights               │
└────────────────────────────────────────────────────────────┘
```

---

## Quyết định đã confirm ✅

| Quyết định | Giá trị |
|-----------|---------|
| Region | `ap-southeast-2` (Sydney) |
| Domain | `bd-apa-coi.com` |
| State | Local (S3 backend commented sẵn) |
| Cross-state sharing | `terraform_remote_state` data source |
| Budget | Không giới hạn, destroy sau test |
| Data services | AWS Managed: RDS, ElastiCache, MSK |
| Container registry | **Dual: ECR + GHCR** (CI push cả hai) |
| Service discovery | Cloud Map (ECS) / K8s Service (EKS) |
| Bastion | Bastion Host + SSM Session Manager |
| NAT Gateway | Standard NAT Gateway |
| Observability | Dual: Grafana stack + CloudWatch |
| Fargate storage | EFS cho Phase 8B observability |
| CI/CD auth | OIDC → IAM Role (không dùng Access Key) |

---

## Shared Modules

### 1. `network` — VPC (3 AZs, 9 Subnets)

| Resource | Config |
|----------|--------|
| VPC | 10.0.0.0/16 |
| Public Subnets × 3 | 10.0.1-3.0/24 — ALB, NAT, Bastion |
| Private Subnets × 3 | 10.0.11-13.0/24 — Compute workloads |
| Data Subnets × 3 | 10.0.21-23.0/24 — RDS, Redis, MSK, EFS |
| Internet Gateway | Public → Internet |
| NAT Gateway | Configurable: 1 (save cost) or 3 (HA, per-AZ) |

---

### 2. `security` — SG, IAM

**Security Groups**:

| SG | Inbound Rules |
|----|---------------|
| ALB | 80/443 from 0.0.0.0/0 |
| Applications | From ALB SG |
| Data | From Application SG |
| Observability | From Application SG |
| Bastion | SSH from your IP |
| EFS | NFS (2049) from Application + Observability SG |

**IAM Roles (service-level)**:

| Role | Gắn vào | Permissions |
|------|---------|-------------|
| ECS Task Execution Role | ECS tasks | Pull ECR, read Secrets, write CW Logs |
| ECS Task Role | App containers | Read SSM, write CW Metrics |
| EKS Node Role | EC2 node group | ECR pull, CW, EBS CSI |
| EKS Pod Role (IRSA) | K8s pods | Read SSM, read Secrets Manager |
| Bastion Role | Bastion EC2 | SSM managed instance |
| Key Pair | SSH access | — |

---

### 3. `data` — Managed Services

| Resource | Replaces | Size |
|----------|----------|------|
| RDS PostgreSQL | Docker PostgreSQL | db.t3.micro, single-AZ |
| ElastiCache Redis | Docker Redis | cache.t3.micro |
| MSK Kafka | Docker Kafka | kafka.t3.small, 2 brokers |

---

### 4. `loadbalancer` — ALB & DNS

| Resource | Config |
|----------|--------|
| ALB | Internet-facing |
| Target Groups | api-gateway, web-ui, grafana |
| ACM Certificate | `*.bd-apa-coi.com` |
| Route53 | A record → ALB |

---

### 5. `secrets` — SSM & Secrets Manager

| Resource | Content |
|----------|---------|
| SSM Parameters | DB URL, Redis URL, Kafka brokers, service endpoints |
| Secrets Manager | DB password |

---

### 6. `ecr` — Container Registry

| Resource | Config |
|----------|--------|
| ECR Repos | 1 per service (7 repos) |
| Lifecycle | Keep last 5 images |

---

### 7. `efs` — Shared File System

| Resource | Used By |
|----------|---------|
| EFS File System | Prometheus, Loki, Tempo data (Phase 8B, 8D) |
| EFS Access Points | 1 per observability component |
| EFS Mount Targets | 1 per private subnet |

---

### 8. `bastion` — Jump Host

| Resource | Config |
|----------|--------|
| EC2 t3.micro | Public subnet, SSH + SSM |
| Security Group | SSH from your IP |
| IAM Role | SSM managed instance |

---

### 9. `cicd` — OIDC & GitHub Actions IAM

Setup GitHub Actions → AWS authentication **không cần Access Key**.

| Resource | Mô tả |
|----------|--------|
| OIDC Provider | Trust `token.actions.githubusercontent.com` |
| IAM Role `github-actions-ecr` | Push images lên ECR |
| IAM Role `github-actions-deploy` | Deploy ECS/EKS (Phase sau) |

**Trust Policy**: Chỉ cho phép repo + branch cụ thể assume role

```
GitHub Actions Workflow
    ↓ (OIDC JWT Token)
AWS STS verify token
    ↓ (check repo, branch, audience)
Assume IAM Role
    ↓ (temporary credentials, 1h expire)
Push ECR / Deploy ECS / Run Terraform
```

**Roles chi tiết**:

| Role | Permissions | Condition |
|------|-------------|----------|
| `github-actions-ecr` | `ecr:PushImage`, `ecr:GetAuthorizationToken` | repo:`YOUR_ORG/observability-sample-v2`, branch: `main` |
| `github-actions-deploy` | `ecs:UpdateService`, `eks:DescribeCluster` | repo:`YOUR_ORG/observability-sample-v2`, branch: `main` |

**CI Workflow update**:
```yaml
# Thêm vào _reusable-build-push.yml
permissions:
  id-token: write    # Request OIDC token
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: ap-southeast-2
  # Không cần AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
```

---

## Compute Phases

### Phase 8A: ECS on EC2

**Học**: EC2 management, ECS scheduling, capacity provider

| Component | Config |
|-----------|--------|
| ECS Cluster | EC2 capacity provider |
| ASG | t3.medium, min=2 max=4, ECS-optimized AMI |
| Task Definitions | 1 per service, `awslogs` log driver |
| ECS Services | Cloud Map service discovery |
| Observability | ECS tasks trên cùng EC2 cluster (EBS volumes) |

**CloudWatch**: CW Agent on EC2, Container Insights, CW Logs

---

### Phase 8B: ECS on Fargate

**Học**: Serverless containers, `awsvpc` networking, EFS integration

| Component | Config |
|-----------|--------|
| ECS Cluster | Fargate capacity provider |
| Task Definitions | Fargate-compatible, `awsvpc` mode |
| Auto Scaling | Target tracking (CPU/Memory) |
| Observability | Fargate tasks + **EFS** cho persistent data |

**CloudWatch**: `awslogs` driver (default), Container Insights Fargate

**So sánh key với 8A**:
| | 8A (EC2) | 8B (Fargate) |
|---|---|---|
| EC2 quản lý | Bạn | AWS |
| Startup | Nhanh | ~30s |
| Cost | Per instance | Per task |
| Storage | EBS | EFS |

---

### Phase 8C: EKS + Managed Node Group

**Học**: K8s core (Deployments, Services, Ingress, Helm), IRSA

| Component | Config |
|-----------|--------|
| EKS Cluster | Managed control plane |
| Node Group | t3.medium, min=2 max=4 |
| K8s Resources | Deployments, Services, ConfigMaps, Ingress |
| Helm Charts | Package apps as charts |
| LB Controller | K8s Ingress → ALB |
| Cluster Autoscaler | Scale nodes per pending pods |
| Observability | DaemonSets (node-exporter, Fluent Bit) + StatefulSets (Prometheus, Loki, Tempo) |

**CloudWatch**: Container Insights for EKS, Fluent Bit DaemonSet → CW Logs

---

### Phase 8D: EKS + Fargate Profile (mixed mode)

**Học**: Fargate Profile selectors, mixed scheduling

| Component | Config |
|-----------|--------|
| EKS Cluster | Reuse từ 8C |
| Fargate Profile | namespace=[applications](file:///root/workspace/observability-lab/applications-vm/applications) |
| Node Group | Giữ cho observability (DaemonSet, EBS) |
| CoreDNS | Patched cho Fargate |

**Kiến trúc mixed**:
```
EKS Cluster
├── Node Group (EC2)       ← Observability
│   ├── prometheus, loki, tempo (StatefulSet + EBS)
│   ├── grafana (Deployment)
│   └── node-exporter, fluent-bit (DaemonSet)
│
└── Fargate Profile        ← Applications
    ├── api-gateway, order-service, payment-service
    ├── notification-worker, inventory-worker
    └── fluent-bit sidecar per pod → CW Logs
```

---

## Dual-stack Observability per Phase

| Signal | Self-hosted | AWS-native |
|--------|------------|------------|
| App metrics | Prometheus | — |
| App logs | Loki | CloudWatch Logs |
| Traces | Tempo (OTel) | — |
| Dashboards | Grafana | CloudWatch Dashboards |
| Infra metrics | — | CloudWatch Metrics |
| Container metrics | — | Container Insights |
| DB perf | — | RDS Performance Insights |
| Alerting | Alertmanager | CloudWatch Alarms |

---

## Directory Structure

```
terraform/
├── modules/
│   ├── network/           # VPC, Subnets, IGW, NAT
│   ├── security/          # SG, IAM, Key Pair
│   ├── data/              # RDS, ElastiCache, MSK
│   ├── loadbalancer/      # ALB, Route53, ACM
│   ├── secrets/           # SSM, Secrets Manager
│   ├── ecr/               # Container registries
│   ├── efs/               # Elastic File System
│   ├── bastion/           # Jump host + SSM
│   ├── cicd/              # OIDC Provider + GitHub Actions IAM Roles
│   ├── ecs-ec2/           # Phase 8A
│   ├── ecs-fargate/       # Phase 8B
│   ├── eks-nodegroup/     # Phase 8C
│   └── eks-fargate/       # Phase 8D
│
├── environments/
│   ├── shared/            # Network, Security, Data, ALB, ECR, EFS, Bastion, OIDC
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf    # S3 (commented)
│   │
│   ├── phase-8a/          # ECS on EC2
│   ├── phase-8b/          # ECS on Fargate + EFS
│   ├── phase-8c/          # EKS + Node Group
│   └── phase-8d/          # EKS + Fargate Profile
│
└── README.md
```

---

## Deployment Workflow

```
# 1. Deploy shared infra (1 lần)
terraform apply -chdir=environments/shared

# 2. Test Phase 8A
terraform apply  -chdir=environments/phase-8a
# → Learn → Destroy
terraform destroy -chdir=environments/phase-8a

# 3. Test Phase 8B
terraform apply  -chdir=environments/phase-8b
# → Learn, compare vs 8A → Destroy
terraform destroy -chdir=environments/phase-8b

# 4. Test Phase 8C
terraform apply  -chdir=environments/phase-8c
# → Learn K8s → Destroy
terraform destroy -chdir=environments/phase-8c

# 5. Test Phase 8D
terraform apply  -chdir=environments/phase-8d
# → Learn mixed mode → Destroy
terraform destroy -chdir=environments/phase-8d

# 6. Cleanup
terraform destroy -chdir=environments/shared
```

---

## Estimated Cost (when running)

| Resource | $/hr | $/day |
|----------|------|-------|
| NAT Gateway | $0.045 | $1.08 |
| MSK (2 brokers) | $0.21 | $5.04 |
| RDS (t3.micro) | $0.018 | $0.43 |
| ElastiCache (t3.micro) | $0.017 | $0.41 |
| ALB | $0.023 | $0.54 |
| ECS/EC2 (2x t3.medium) | $0.084 | $2.02 |
| EFS | ~$0.01 | ~$0.24 |
| Bastion (t3.micro) | $0.01 | $0.25 |
| **Total shared + 1 phase** | **~$0.42** | **~$10** |

> [!TIP]
> `terraform destroy` → **$0/day**. Apply sáng, destroy tối ≈ $10/ngày.

---

## Implementation Order

| Step | What | Modules |
|------|------|---------|
| 1 | Shared infra | network → security → data → loadbalancer → secrets → ecr → efs → bastion → cicd |
| 2 | CI update | Add ECR push + OIDC auth to [_reusable-build-push.yml](file:///root/workspace/observability-sample-v2/.github/workflows/_reusable-build-push.yml) |
| 3 | Phase 8A | ecs-ec2 module → deploy → test → destroy |
| 4 | Phase 8B | ecs-fargate module → deploy → compare → destroy |
| 5 | Phase 8C | eks-nodegroup module → deploy → test → destroy |
| 6 | Phase 8D | eks-fargate module → deploy → compare → destroy |
