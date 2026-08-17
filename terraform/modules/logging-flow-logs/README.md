# Logging — Flow Logs Module

Production-grade centralized log storage with S3 lifecycle tiering, KMS encryption, and Athena query-ready Glue catalog for VPC Flow Logs forensic analysis.

## Architecture

```
Logging Module
├── S3 Bucket              Flow log archive, versioned, SSE-KMS, TLS enforced
│   └── Lifecycle          Standard (0-90d) → Glacier (90-365d) → Delete
├── KMS CMK                Dedicated key for S3 encryption (defense-in-depth)
├── Glue Database          Catalog for Athena SQL queries
│   └── Glue Table         VPC Flow Logs v2 schema, partition projection
└── Athena Workgroup       Encrypted query results, enforced configuration
```

## Usage

```hcl
module "logging" {
  source = "../../modules/logging"

  project_name = "observability"
  environment  = "lab"

  # Lifecycle: Standard → Glacier → Delete
  flow_logs_glacier_transition_days = 90   # Move to Glacier after 90 days
  flow_logs_expiration_days         = 365  # Delete after 1 year

  common_tags = {
    Module = "logging"
  }
}

# Pass bucket ARN to network module for S3 flow log destination
module "network" {
  source = "../../modules/network"
  # ...
  flow_logs_s3_bucket_arn = module.logging.flow_logs_bucket_arn
}
```

**Query flow logs with Athena:**
```sql
SELECT srcaddr, dstaddr, dstport, action, protocol, packets
FROM vpc_flow_logs
WHERE region = 'ap-southeast-2'
  AND date = '2025/01/15'
  AND action = 'REJECT'
ORDER BY packets DESC
LIMIT 100;
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name for resource naming | `string` | — | ✅ |
| `environment` | Environment name | `string` | `"lab"` | no |
| `flow_logs_glacier_transition_days` | Days before Glacier transition | `number` | `90` | no |
| `flow_logs_expiration_days` | Days before permanent deletion | `number` | `365` | no |
| `athena_query_result_retention_days` | Days to retain query results | `number` | `7` | no |
| `common_tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `flow_logs_bucket_arn` | S3 bucket ARN for VPC Flow Logs |
| `flow_logs_bucket_id` | S3 bucket name/ID |
| `flow_logs_kms_key_arn` | KMS key ARN for S3 encryption |
| `flow_logs_kms_key_id` | KMS key ID |
| `athena_database_name` | Glue catalog database name |
| `athena_table_name` | Glue catalog table name |
| `athena_workgroup_name` | Athena workgroup name |

## File Structure

```
logging-flow-logs/
├── versions.tf        # Terraform >= 1.5.0, AWS ~> 5.0
├── variables.tf       # 6 input variables with validation
├── kms.tf             # CMK for S3 encryption + data sources
├── s3.tf              # S3 bucket, policy, versioning, lifecycle
├── athena.tf          # Glue catalog + Athena workgroup
├── outputs.tf         # 7 outputs
├── README.md          # This file
└── CHANGELOG.md       # Version history
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate module from network | Log storage lifecycle ≠ VPC lifecycle. Destroying VPC must not destroy archive. |
| Partition projection (not crawlers) | Zero-cost, zero-maintenance. No Glue crawler runs or MSCK REPAIR TABLE needed. |
| Bucket key enabled | Reduces KMS `GenerateDataKey` API calls by ~99% for high-volume flow log writes. |
| Dedicated CMK (not shared) | Defense-in-depth — separate from CloudWatch flow logs key and backup vault key. |
| `delivery.logs.amazonaws.com` | S3 flow log destination uses this service principal, no IAM role needed (unlike CloudWatch). |
| Enforce TLS | Deny all unencrypted S3 operations to meet CIS AWS 2.1.1. |

## Environment Scaling

| Config | Lab | Staging | Production (SOC 2) | Production (HIPAA) |
|--------|-----|---------|-------------------|--------------------|
| `flow_logs_glacier_transition_days` | `90` | `90` | `90` | `180` |
| `flow_logs_expiration_days` | `365` | `365` | `365` | `2190` (6 years) |
| S3 Lifecycle | Standard→Glacier→Delete | Same | Same | Standard→Glacier→Delete |

## Cost Estimate (Lab)

| Resource | Monthly Cost |
|----------|-------------|
| S3 Standard (~1 GB flow logs) | ~$0.02 |
| S3 Glacier (after 90d, ~3 GB) | ~$0.01 |
| KMS key (1 CMK) | ~$1.00 |
| Glue catalog | Free tier |
| Athena queries (pay-per-scan) | ~$0.005/query |
| **Total** | **~$1.03/month** |

## Related Modules

- [`network`](../network/) — Creates `aws_flow_log.s3` pointing to this bucket
- [`backup`](../backup/) — Similar KMS + S3 pattern for backup reports
