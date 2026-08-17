# Backup Module

Production-grade AWS Backup module with centralized vault management, cross-region copy (DR Tier 1), tag-based auto-discovery, vault lock protection, and SNS/CloudWatch monitoring.

## Architecture

```
Backup Module
├── Vault (primary)        KMS-encrypted, vault lock, access policy (deny delete)
├── Vault (DR region)      Cross-region copy destination, same protections
├── Backup Plan
│   ├── Daily rule         3 AM UTC, 35-day retention
│   └── Monthly rule       1st of month, 365-day retention, cold storage after 30d
├── Selection              Tag-based: Backup=true (auto-discover)
├── KMS Keys               Separate CMKs for primary + DR vaults
├── IAM Role               AWS managed policies (backup + restore + S3)
├── SNS Topic              KMS-encrypted, backup/copy/restore events
└── CloudWatch Alarms      Backup job + copy job failure detection
```

## Usage

```hcl
module "backup" {
  source = "../../modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr  # DR region provider alias
  }

  project_name = "observability"
  environment  = "lab"

  # Vault
  vault_lock_mode = "governance"  # "compliance" for regulated envs

  # Daily backup
  daily_schedule       = "cron(0 3 * * ? *)"
  daily_retention_days = 35

  # Monthly backup (long-term)
  enable_monthly_plan    = true
  monthly_retention_days = 365

  # Cross-region copy (DR Tier 1)
  enable_cross_region_copy        = true   # false to disable DR
  cross_region_copy_retention_days = 35

  # Notifications
  notification_email       = "ops@example.com"
  enable_cloudwatch_alarms = true

  common_tags = {
    Module = "backup"
  }
}
```

**To protect a resource**, add the tag `Backup = "true"` to it:
```hcl
# Example: in database module
tags = { Backup = "true" }
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name for resource naming | `string` | — | ✅ |
| `environment` | Environment name | `string` | `"lab"` | no |
| `vault_lock_mode` | `governance` or `compliance` | `string` | `"governance"` | no |
| `vault_lock_min_retention_days` | Minimum retention enforced by vault lock | `number` | `1` | no |
| `vault_lock_max_retention_days` | Maximum retention enforced by vault lock | `number` | `365` | no |
| `daily_schedule` | Cron expression for daily backup (UTC) | `string` | `"cron(0 3 * * ? *)"` | no |
| `daily_retention_days` | Days to retain daily backups | `number` | `35` | no |
| `enable_monthly_plan` | Enable monthly long-term backup | `bool` | `true` | no |
| `monthly_retention_days` | Days to retain monthly backups | `number` | `365` | no |
| `monthly_cold_storage_after_days` | Move monthly to cold storage after N days | `number` | `30` | no |
| `enable_cross_region_copy` | Enable cross-region backup copy | `bool` | `true` | no |
| `cross_region_copy_retention_days` | DR copy retention in days | `number` | `35` | no |
| `selection_tag_key` | Tag key for auto-discovery | `string` | `"Backup"` | no |
| `selection_tag_value` | Tag value for auto-discovery | `string` | `"true"` | no |
| `notification_email` | Email for failure alerts (empty = skip) | `string` | `""` | no |
| `enable_cloudwatch_alarms` | Create CloudWatch alarms | `bool` | `true` | no |
| `common_tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vault_arn` | Primary backup vault ARN |
| `vault_name` | Primary backup vault name |
| `vault_dr_arn` | DR vault ARN (null if disabled) |
| `plan_id` | Backup plan ID |
| `plan_arn` | Backup plan ARN |
| `backup_role_arn` | IAM role ARN for AWS Backup |
| `kms_key_arn` | Primary vault KMS key ARN |
| `kms_key_dr_arn` | DR vault KMS key ARN (null if disabled) |
| `sns_topic_arn` | SNS topic ARN (reusable by other modules) |
| `selection_tag` | Tag key/value to add to resources for protection |

## File Structure

```
backup/
├── versions.tf        # Provider (aws + aws.dr alias)
├── variables.tf       # 17 input variables with validation
├── vault.tf           # Vaults + lock + access policy (primary + DR)
├── plan.tf            # Backup plan (daily/monthly) + selection
├── kms.tf             # KMS CMKs (primary + DR) + data sources
├── iam.tf             # Backup service role + 4 managed policies
├── notifications.tf   # SNS topic + vault events + CW alarms
├── outputs.tf         # 10 outputs
├── examples/          # Usage examples
│   └── basic/
├── tests/             # Contract tests
│   └── contract.tftest.hcl
├── README.md          # This file
└── CHANGELOG.md       # Version history
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate KMS keys (primary + DR) | Defense-in-depth — compromising one key doesn't expose backups in the other region |
| Vault access policy (deny delete) | Even a compromised IAM admin cannot delete recovery points |
| Tag-based selection (`Backup=true`) | Auto-discovers new resources without Terraform changes |
| `aws.dr` provider alias | Module creates DR resources in a different region via passed-in provider |
| Governance vault lock (default) | Admin can override for lab flexibility; use `compliance` for regulated envs |
| Precondition validation | Catches retention > vault_lock_max at plan time, not runtime |

## Environment Scaling

| Config | Lab | Staging | Production |
|--------|-----|---------|------------|
| `vault_lock_mode` | `governance` | `governance` | `compliance` |
| `daily_retention_days` | `7` | `35` | `35` |
| `enable_monthly_plan` | `false` | `true` | `true` |
| `monthly_retention_days` | — | `90` | `365` |
| `enable_cross_region_copy` | `false` | `true` | `true` |
| `notification_email` | `""` | `ops@...` | `ops@...` |

## Cost Estimate (Lab)

| Resource | Monthly Cost |
|----------|-------------|
| Backup vault storage (warm, ~1 GB) | ~$0.05 |
| KMS key (1 CMK) | ~$1.00 |
| SNS topic | Free tier |
| CloudWatch alarms (2) | ~$0.20 |
| **Total (no DR)** | **~$1.25/month** |
| **Total (with DR)** | **~$2.50/month** |

## Related Modules

- [`database`](../database/) — RDS PostgreSQL (tagged `Backup=true`)
- [`efs`](../efs/) — Elastic File System (future, will add `Backup=true`)
- [`dr`](../dr/) — Pilot Light DR (future, uses DR vault outputs)
