# Security Module

Production-grade AWS security module with defense-in-depth Security Groups, least-privilege IAM Roles, and dual-mode SSH Key Pair management.

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

**Pattern:** All inter-tier rules use `source_security_group_id` (not CIDRs). Traffic is only allowed between resources that are **members** of the correct Security Group. Reference: [AWS Well-Architected SEC05-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_create_layers.html).

## Usage

```hcl
module "security" {
  source = "../../modules/security"

  # Required
  project_name   = "my-project"
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.vpc_cidr_block

  # Application
  app_port = 8080

  # Bastion (set enable_bastion = false to skip)
  enable_bastion    = true
  allowed_ssh_cidrs = ["1.2.3.4/32"]
  generate_ssh_key  = true  # false in production

  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Resources Created

| Resource | Count | Conditional |
|----------|-------|-------------|
| Security Groups | 5-6 | Bastion SG conditional |
| SG Rules | ~30 | Varies by db_ports/monitoring_ports |
| IAM Roles | 2-3 | Bastion role conditional |
| IAM Policies | 4-5 | Bastion policies conditional |
| Key Pair | 0-1 | Based on enable_bastion + generate_ssh_key |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `project_name` | `string` | — | ✅ | Project name (lowercase, digits, hyphens) |
| `vpc_id` | `string` | — | ✅ | VPC ID (validated: `vpc-*`) |
| `vpc_cidr_block` | `string` | — | ✅ | VPC CIDR for internal rules |
| `app_port` | `number` | `8080` | no | Application container port (1-65535) |
| `app_health_check_port` | `number` | `0` | no | Health check port (0 = same as app_port) |
| `enable_bastion` | `bool` | `true` | no | Toggle bastion resources (SG, IAM, Key Pair) |
| `allowed_ssh_cidrs` | `list(string)` | `[]` | no | CIDRs allowed SSH to bastion |
| `generate_ssh_key` | `bool` | `true` | no | Auto-generate SSH key pair (false for production) |
| `public_key_path` | `string` | `""` | no | SSH public key path (when generate_ssh_key = false) |
| `db_ports` | `map(number)` | postgres/mysql/redis/kafka | no | DB ports for Data SG ingress |
| `monitoring_ports` | `map(number)` | prometheus/grafana/loki/tempo/node_exporter | no | Monitoring ports for Observability SG |
| `kms_key_arn` | `string` | `""` | no | KMS key ARN for secrets encryption |
| `common_tags` | `map(string)` | `{}` | no | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `alb_security_group_id` | ALB Security Group ID |
| `application_security_group_id` | Application Security Group ID |
| `data_security_group_id` | Data tier Security Group ID |
| `efs_security_group_id` | EFS Security Group ID |
| `observability_security_group_id` | Observability Security Group ID |
| `bastion_security_group_id` | Bastion Security Group ID (empty string if disabled) |
| `security_group_ids` | Map of all SG IDs (`{alb, application, data, efs, observability, bastion}`) |
| `ecs_task_execution_role_arn` | ECS Task Execution Role ARN (infra-level) |
| `ecs_task_execution_role_name` | ECS Task Execution Role name |
| `ecs_task_role_arn` | ECS Task Role ARN (app-level) |
| `ecs_task_role_name` | ECS Task Role name |
| `bastion_instance_profile_name` | Bastion Instance Profile name (empty if disabled) |
| `bastion_instance_profile_arn` | Bastion Instance Profile ARN (empty if disabled) |
| `bastion_role_arn` | Bastion IAM Role ARN (empty if disabled) |
| `key_pair_name` | SSH Key Pair name (empty if disabled) |

## File Structure

```
security/
├── security_groups.tf   # 6-tier SGs with inter-tier rules
├── iam_ecs.tf           # ECS Task Execution + Task roles
├── iam_bastion.tf       # Bastion Instance Profile + SSM
├── key_pair.tf          # Dual-mode SSH key (lab/production)
├── variables.tf         # Input variables with validation
├── outputs.tf           # Module outputs (IDs, ARNs, maps)
├── versions.tf          # Provider constraints (~> 5.0)
├── CHANGELOG.md         # Release history
└── tests/
    ├── setup/
    │   └── main.tf                 # Helper: minimal VPC for testing
    ├── contract.tftest.hcl         # 8 plan-only tests (variable validation)
    └── integration.tftest.hcl      # 9 apply+destroy tests (real resources)
```

## Testing

### Contract Tests (Plan Only — $0, ~15s)

```bash
cd terraform/modules/security
terraform init
terraform test -filter=tests/contract.tftest.hcl
```

Validates variable constraints without creating AWS resources:
- Input validation (project_name regex, vpc_id format, port ranges, CIDR format)
- Default values (app_port=8080, enable_bastion=true, etc.)

### Integration Tests (Apply + Destroy — ~$0.02, ~3min)

```bash
terraform test -filter=tests/integration.tftest.hcl
```

Creates **real AWS resources** and validates:

| # | Test | What It Validates |
|---|------|-------------------|
| 0 | `setup_vpc` | Helper VPC for SG creation |
| 1 | `core_security_groups_created` | 6 SGs with valid `sg-*` IDs |
| 2 | `all_security_groups_are_unique` | No shared SG IDs (defense-in-depth) |
| 3 | `sg_map_output_has_correct_keys` | Map output has all 6 keys |
| 4 | `ecs_iam_roles_created` | Execution + Task roles separate |
| 5 | `bastion_iam_created_when_enabled` | Instance Profile + Role |
| 6 | `ssh_key_generated_in_lab_mode` | Auto-generated key pair |
| 7 | `tags_applied_to_security_groups` | Tier + common_tags on resources |
| 8 | `bastion_disabled_removes_resources` | Toggle OFF → empty strings |
| 9 | `bastion_re_enabled_creates_resources` | Toggle ON → clean teardown |

**Prerequisites:** Valid AWS credentials with permissions for VPC, Security Groups, IAM, EC2 Key Pairs.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| `source_security_group_id` over CIDRs | Enforces that traffic flows only between SG members, not arbitrary IPs |
| `name_prefix` over `name` | Enables `create_before_destroy` lifecycle — avoids name conflicts during replacement |
| Separate Execution vs Task roles | Least-privilege: infra ops (ECR pull, logs) separated from app ops (S3, SQS) |
| Bastion via SSM | No inbound port 22 from Internet — audit-friendly, no public IP needed |
| `for_each` on db_ports/monitoring_ports | Adding a new DB port doesn't recreate existing SG rules |
| Conditional bastion (`count`) | Production environments can disable bastion entirely |
| Dual-mode key pair | Lab: auto-generate for convenience. Production: import from Vault/1Password |
| Test helper VPC | Integration tests don't depend on network module — isolated testing |

## Cost Considerations

| Resource | Cost |
|----------|------|
| Security Groups | Free |
| Security Group Rules | Free |
| IAM Roles/Policies | Free |
| EC2 Key Pair | Free |
| **Total** | **$0/month** |

> **Note:** This module creates only IAM and VPC-level resources. All are free-tier. Cost is incurred only by compute resources (EC2, ECS, ALB) that **reference** these security groups.

## Related Modules

- [`network`](../network/) — VPC, subnets, NAT Gateways, routing (provides `vpc_id` + `vpc_cidr_block`)
- [`vpc-endpoints`](../vpc-endpoints/) — Interface + Gateway endpoints (uses Security Groups from this module)
