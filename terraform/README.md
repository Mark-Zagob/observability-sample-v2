# ☁️ Terraform — AWS Infrastructure

> Production-grade AWS infrastructure cho Observability Lab, triển khai bằng Terraform với OPA policy-as-code.

## Tài Liệu

| File | Nội dung |
|------|---------|
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Chi tiết modules, deployment order, DR strategy |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Sơ đồ Mermaid — VPC topology, security flow, CI/CD |
| [policy/README.md](policy/README.md) | OPA/Rego policy-as-code guide |

---

## Tiến Độ

| Layer | Modules | Trạng thái |
|-------|---------|-----------|
| **Foundation** | network, vpc-endpoints, security, logging | ✅ Done |
| **Data** | database (RDS) | ✅ Done |
| **Data** | cache (ElastiCache), streaming (MSK) | 🔲 TODO |
| **Platform** | ecr, efs, loadbalancer | 🔲 TODO |
| **Operations** | bastion, cicd, backup, budgets | 🔲 TODO |
| **Compute** | ecs-ec2, ecs-fargate, eks-nodegroup, eks-fargate | 🔲 TODO |
| **DR** | Pilot Light (cross-region) | 🔲 TODO |

---

## Quick Start

### Prerequisites

- Terraform ≥ 1.7.0
- AWS CLI configured (`aws configure`)
- S3 backend bootstrapped (xem `bootstrap/`)

### Deploy shared infrastructure

```bash
cd environments/shared
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

### Validate với OPA

```bash
cd environments/shared
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
conftest test plan.json -p ../../policy/
```

### Destroy

```bash
cd environments/shared
terraform destroy
```

---

## Cấu Trúc

```
terraform/
├── README.md                     ← File này
├── IMPLEMENTATION_PLAN.md        ← Chi tiết modules + deployment order
├── ARCHITECTURE.md               ← Sơ đồ Mermaid kiến trúc AWS
├── devops-question-m1-iac-core.md ← DevOps interview (IaC Core)
├── bootstrap/                    # S3 + DynamoDB state backend
├── modules/                      # Reusable Terraform modules
│   ├── network/              ✅
│   ├── vpc-endpoints/        ✅
│   ├── security/             ✅
│   ├── database/             ✅
│   ├── backup/               ✅
│   ├── logging-flow-logs/    ✅  # S3 + Athena for flow log archive
│   └── ... (xem IMPLEMENTATION_PLAN.md)
├── environments/
│   ├── shared/               ✅  # Shared infra (S3 backend)
│   └── dev/                      # Terraform Cloud backend (testing)
└── policy/                   ✅  # OPA/Rego policies + tests
```

---

## 📝 DevOps Interview Practice

Bộ câu hỏi phỏng vấn DevOps dựa trên Terraform/AWS infrastructure:

| File | Level | Số câu | Focus |
|------|-------|--------|-------|
| [devops-question-m1-iac-core.md](devops-question-m1-iac-core.md) | Junior–Mid + Senior | 54 | Terraform fundamentals, state, modules, architecture, troubleshooting |
| M2: Networking & Security | 🔲 Planned | — | VPC, IAM, KMS, OPA, multi-account |
| M3: DR, Backup & Compliance | 🔲 Planned | — | RPO/RTO, vault lock, checkov, compliance |

> Câu hỏi dựa trên modules thực tế trong repo này. Thêm milestones mới sau mỗi module hoàn thành.

---

## State Management

| Environment | Backend | State Key |
|-------------|---------|-----------|
| `shared` | S3 + DynamoDB | `shared/terraform.tfstate` |
| `dev` | Terraform Cloud | workspace: `obs-dev` |

> Chi tiết: xem `environments/shared/backend.tf`
