# Network Module

Production-grade AWS VPC module with 4-tier subnet architecture, compact CIDR allocation, NAT Gateway HA options, and VPC Flow Logs.

## Architecture

```
VPC /16
├── Private Subnets  /20 × 3 AZs  (EKS pods, ECS tasks, EC2)
├── Public Subnets   /24 × 3 AZs  (ALB, NAT Gateway)
├── Data Subnets     /26 × 3 AZs  (RDS, ElastiCache, MSK)
└── Mgmt Subnets     /27 × 3 AZs  (Bastion, VPN, CI runners)
```

**CIDR Strategy:** VPC split into 2 halves (`/17`). First half dedicated to Private subnets (large IP pool for EKS VPC CNI). Second half subdivided for Public, Data, and Mgmt tiers with 6 × `/20` blocks reserved for future expansion.

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  project_name       = "my-project"
  aws_region         = "ap-southeast-2"
  vpc_cidr           = "10.0.0.0/16"
  az_count           = 3
  single_nat_gateway = false  # true for cost-saving, false for HA

  enable_flow_logs        = true
  flow_logs_retention_days = 30

  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name for resource naming (lowercase, digits, hyphens only) | `string` | — | ✅ |
| `aws_region` | AWS region (e.g. `ap-southeast-2`) | `string` | — | ✅ |
| `vpc_cidr` | VPC CIDR block (must be `/16`) | `string` | `10.0.0.0/16` | no |
| `az_count` | Number of AZs (2 or 3) | `number` | `3` | no |
| `single_nat_gateway` | Single NAT (cost-saving) vs per-AZ NAT (HA) | `bool` | `true` | no |
| `enable_flow_logs` | Enable VPC Flow Logs to CloudWatch | `bool` | `true` | no |
| `flow_logs_retention_days` | CloudWatch log retention (valid CW values) | `number` | `7` | no |
| `common_tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `data_subnet_ids` | List of data subnet IDs |
| `mgmt_subnet_ids` | List of management subnet IDs |
| `public_subnets` | Map of AZ key → public subnet attributes |
| `private_subnets` | Map of AZ key → private subnet attributes |
| `nat_gateway_ids` | NAT Gateway IDs |
| `nat_public_ips` | NAT Gateway Elastic IPs |
| `internet_gateway_id` | Internet Gateway ID |
| `public_route_table_id` | Public route table ID |
| `private_route_table_ids` | Map of AZ key → private route table ID |
| `mgmt_route_table_ids` | Map of AZ key → mgmt route table ID |
| `data_route_table_id` | Data route table ID |

## File Structure

```
network/
├── vpc.tf          # VPC + Internet Gateway
├── subnets.tf      # 4-tier subnets (public, private, data, mgmt)
├── routing.tf      # Route tables + associations
├── nat.tf          # EIPs + NAT Gateways
├── flow_logs.tf    # VPC Flow Logs + IAM
├── data.tf         # Data sources + CIDR locals
├── variables.tf    # Input variables with validation
├── outputs.tf      # Module outputs
└── versions.tf     # Provider constraints
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| `for_each` over `count` | Stable resource addressing — adding/removing AZs doesn't shift indices |
| 4-tier subnet model | Separation of concerns: workloads, ingress, data, management |
| `/20` for Private | EKS VPC CNI: 1 IP per pod → 4,096 IPs per AZ |
| Compact CIDR packing | Data (`/26`) + Mgmt (`/27`) share one `/20` block → saves 8,192 IPs |
| Per-AZ route tables | Private/Mgmt get per-AZ tables for AZ-aware NAT routing |
| Single shared Data RT | Data tier has no internet route — pure isolation |

## Cost Considerations

| Resource | Single NAT | HA (3 NAT) |
|----------|-----------|------------|
| NAT Gateway | ~$1/day | ~$3/day |
| EIP | Free (attached) | Free (attached) |
| Flow Logs | ~$0.50/GB ingested | ~$0.50/GB |

## Related Modules

- [`vpc-endpoints`](../vpc-endpoints/) — S3/DynamoDB Gateway + Interface Endpoints (extracted per SRP)
