# Security Module

Manages Security Groups, IAM Roles, and SSH Key Pairs for the production infrastructure.

## Architecture

```
Internet → [ALB SG: 80/443]
               │ source_security_group_id
               ▼
           [App SG: app_port from ALB]
               │ source_security_group_id
               ├──→ [Data SG: DB ports from App + Bastion]
               ├──→ [EFS SG: 2049 from App]
               └──→ [Obs SG: monitoring ports from VPC]

           [Bastion SG: 22 from allowed_ssh_cidrs]
               └──→ App SG + Data SG (admin access)
```

## Usage

```hcl
module "security" {
  source = "../../modules/security"

  project_name   = "my-project"
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.vpc_cidr_block

  # Application
  app_port = 8080

  # Bastion (set enable_bastion = false to skip)
  enable_bastion    = true
  allowed_ssh_cidrs = ["1.2.3.4/32"]
  generate_ssh_key  = true  # false in production

  common_tags = { Environment = "shared" }
}
```

## Resources Created

| Resource | Count | Conditional |
|----------|-------|-------------|
| Security Groups | 5-6 | Bastion SG conditional |
| SG Rules | ~30 | Varies by db_ports/monitoring_ports |
| IAM Roles | 2-3 | Bastion role conditional |
| IAM Policies | 4-5 | Bastion policies conditional |
| Key Pair | 0-1 | Based on enable_bastion |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_name` | `string` | — | Project name (lowercase, digits, hyphens) |
| `vpc_id` | `string` | — | VPC ID |
| `vpc_cidr_block` | `string` | — | VPC CIDR for internal rules |
| `app_port` | `number` | `8080` | Application container port |
| `enable_bastion` | `bool` | `true` | Toggle bastion resources |
| `allowed_ssh_cidrs` | `list(string)` | `[]` | CIDRs allowed SSH to bastion |
| `generate_ssh_key` | `bool` | `true` | Auto-generate SSH key pair |
| `db_ports` | `map(number)` | postgres/mysql/redis/kafka | DB ports for Data SG |
| `monitoring_ports` | `map(number)` | prometheus/grafana/loki/tempo | Monitoring ports |

## Outputs

| Name | Description |
|------|-------------|
| `alb_security_group_id` | ALB SG ID |
| `application_security_group_id` | App SG ID |
| `data_security_group_id` | Data SG ID |
| `efs_security_group_id` | EFS SG ID |
| `observability_security_group_id` | Observability SG ID |
| `bastion_security_group_id` | Bastion SG ID (empty if disabled) |
| `security_group_ids` | Map of all SG IDs |
| `ecs_task_execution_role_arn` | ECS Task Execution Role ARN |
| `ecs_task_role_arn` | ECS Task Role ARN |
| `bastion_instance_profile_name` | Bastion Instance Profile |
| `key_pair_name` | SSH Key Pair name |
