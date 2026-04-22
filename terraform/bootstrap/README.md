# Bootstrap — Terraform State Infrastructure

Production-grade state backend: S3 + DynamoDB + KMS.

## Architecture

```
┌──────────────────────────────────────┐
│         S3 Bucket (State)            │
│  ✅ KMS encryption (CMK)            │
│  ✅ Versioning (rollback)            │
│  ✅ Access logging → Log bucket      │
│  ✅ Bucket policy (HTTPS + KMS only) │
│  ✅ Block public access              │
│  ✅ Lifecycle (90d noncurrent)       │
└────────────────┬─────────────────────┘
                 │
┌────────────────▼─────────────────────┐
│       DynamoDB Table (Locks)         │
│  ✅ On-demand billing (~$0)          │
│  ✅ Point-in-time recovery           │
│  ✅ Server-side encryption           │
└──────────────────────────────────────┘
```

## Usage

```bash
# Step 1: Create state infrastructure
cd terraform/bootstrap
terraform init
terraform plan
terraform apply

# Step 2: Copy output values to backend.tf
# The 'backend_config_snippet' output provides a ready-to-paste block.

# Step 3: Migrate existing state
cd ../environments/shared
# Update backend.tf with output values, then:
terraform init -migrate-state
# Type "yes" when prompted to move state from local to S3
```

## Cost

| Resource | Monthly Cost |
|----------|-------------|
| S3 Standard (< 1MB state) | ~$0.02 |
| DynamoDB on-demand | ~$0.01 |
| KMS CMK | $1.00 |
| S3 access logs | ~$0.01 |
| **Total** | **~$1.04** |

## Recovery

If bootstrap state is lost (local file deleted):

```bash
terraform import aws_s3_bucket.state BUCKET_NAME
terraform import aws_s3_bucket.logs LOG_BUCKET_NAME
terraform import aws_dynamodb_table.locks terraform-state-locks
terraform import aws_kms_key.state KEY_ID
terraform import aws_kms_alias.state alias/obs-terraform-state
```
