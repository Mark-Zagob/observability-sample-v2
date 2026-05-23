#--------------------------------------------------------------
# Backup Module — Report Plan & Region Settings
#--------------------------------------------------------------
# Compliance reporting: automated daily reports to S3.
# Region settings: explicit opt-in for AWS Backup supported services.
#
# Reference: AWS Well-Architected REL09-BP03
#--------------------------------------------------------------

########################################################################
# 1. AWS Backup Region Settings — Explicit Service Opt-In
########################################################################
# AWS Backup must be explicitly enabled for each service type.
# Default is opt-in for most services, but being explicit prevents
# surprises when tag-based selection silently skips a service.
########################################################################

resource "aws_backup_region_settings" "primary" {
  resource_type_opt_in_preference = {
    "Aurora"          = true
    "DocumentDB"      = false
    "DynamoDB"        = true
    "EBS"             = true
    "EC2"             = false # Don't backup EC2 instances (use ASG/launch templates)
    "EFS"             = true
    "FSx"             = false
    "Neptune"         = false
    "RDS"             = true
    "S3"              = true
    "Storage Gateway" = false
    "VirtualMachine"  = false
  }

  resource_type_management_preference = {
    "DynamoDB" = true # Enable advanced DynamoDB backup features
    "EFS"      = true # Enable EFS backup features
  }
}

########################################################################
# 2. S3 Bucket — Backup Reports Destination
########################################################################
# Stores compliance reports (CSV) that prove backups ran as expected.
# Auditor asks "prove backup ran 30 days?" → point to this bucket.
#
# Security hardening:
#   - KMS-SSE encryption (same CMK as vault)
#   - Bucket policy: deny unencrypted uploads + enforce TLS
#   - Public access block (4 flags)
#   - Ownership controls (BucketOwnerEnforced — disables ACLs)
#   - Versioning enabled
#   - Lifecycle auto-expiry
########################################################################

#checkov:skip=CKV_AWS_145:KMS encryption configured in aws_s3_bucket_server_side_encryption_configuration.backup_reports
#checkov:skip=CKV_AWS_21:Versioning configured in aws_s3_bucket_versioning.backup_reports
#checkov:skip=CKV2_AWS_6:Public access block configured in aws_s3_bucket_public_access_block.backup_reports
#checkov:skip=CKV2_AWS_61:Lifecycle configured in aws_s3_bucket_lifecycle_configuration.backup_reports
#checkov:skip=CKV_AWS_144:Cross-region replication not needed — reports are regenerable, actual backups ARE cross-region copied
#checkov:skip=CKV2_AWS_62:Event notifications not needed for compliance CSV report bucket
resource "aws_s3_bucket" "backup_reports" {
  count = var.enable_backup_reports ? 1 : 0

  bucket        = "${local.identifier}-reports-${local.account_id}"
  force_destroy = var.environment != "prod" # Allow destroy in non-prod

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-reports"
    Component = "backup"
    Purpose   = "compliance-reports"
  })
}

#--------------------------------------------------------------
# Ownership Controls — Disable ACLs (modern S3 best practice)
#--------------------------------------------------------------
# BucketOwnerEnforced = all objects owned by bucket owner,
# ACLs are disabled entirely. Prevents accidental public ACLs.
#--------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#--------------------------------------------------------------
# Access Logging — audit trail for bucket access
#--------------------------------------------------------------
# Logs all access to the report bucket. Uses server access logging
# to a "logs/" prefix within the same bucket (self-logging pattern).
# For enterprise: use a dedicated centralized logging bucket.
#--------------------------------------------------------------
#checkov:skip=CKV_AWS_18:Access logging configured in aws_s3_bucket_logging.backup_reports
resource "aws_s3_bucket_logging" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  target_bucket = aws_s3_bucket.backup_reports[0].id
  target_prefix = "access-logs/"
}

#--------------------------------------------------------------
# Bucket Policy — Enforce TLS + Deny Unencrypted Uploads
#--------------------------------------------------------------
# Two critical security controls:
# 1. Deny any request NOT using HTTPS (prevent MitM)
# 2. Deny PutObject without KMS encryption header
# 3. Allow AWS Backup service to write reports
#--------------------------------------------------------------
resource "aws_s3_bucket_policy" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.backup_reports]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backup_reports[0].arn,
          "${aws_s3_bucket.backup_reports[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.backup_reports[0].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid    = "AllowBackupReportDelivery"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.backup_reports[0].arn,
          "${aws_s3_bucket.backup_reports[0].arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_reports" {
  count  = var.enable_backup_reports ? 1 : 0
  bucket = aws_s3_bucket.backup_reports[0].id

  rule {
    id     = "expire-old-reports"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_reports_retention_days
    }

    # Clean up old versions too
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # CKV_AWS_300: Abort incomplete multipart uploads after 7 days
  # Prevents orphaned multipart uploads from accumulating storage cost
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

########################################################################
# 3. Backup Report Plan — Daily Compliance Reports
########################################################################
# Generates CSV reports for all backup jobs:
#   - Which resources were backed up
#   - Success/failure status
#   - Compliance with backup plan rules
########################################################################

resource "aws_backup_report_plan" "compliance" {
  count = var.enable_backup_reports ? 1 : 0

  # AWS report plan names only allow letters, numbers, underscores (no hyphens)
  name        = replace("${local.identifier}-compliance-report", "-", "_")
  description = "Daily backup job compliance report for ${var.project_name}-${var.environment}"

  report_delivery_channel {
    s3_bucket_name = aws_s3_bucket.backup_reports[0].id
    s3_key_prefix  = "backup-reports"
    formats        = ["CSV"]
  }

  report_setting {
    report_template = "BACKUP_JOB_REPORT"
  }

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-compliance-report"
    Component = "backup"
    Purpose   = "compliance"
  })
}
