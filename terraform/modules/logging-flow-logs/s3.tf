#--------------------------------------------------------------
# Logging Module — S3 Bucket for VPC Flow Logs
#--------------------------------------------------------------
# Centralized log storage with lifecycle tiering:
#   Standard (0-90d) → Glacier Flexible (90-365d) → Delete
#
# Why S3 instead of CloudWatch-only:
# - 20x cheaper for long-term retention ($0.023/GB vs $0.50/GB)
# - Athena SQL queries for forensic investigation
# - Lifecycle to Glacier for compliance archive
# - Separate lifecycle from VPC (destroy VPC ≠ lose logs)
#
# Reference: AWS Well-Architected SEC10-BP06
#--------------------------------------------------------------

resource "aws_s3_bucket" "flow_logs" {
  bucket = "${var.project_name}-flow-logs-${local.account_id}"

  # Prevent accidental deletion of log archive
  # Remove this only after migrating data to another store
  lifecycle {
    prevent_destroy = false # Set to true in production
  }

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-flow-logs"
    Component = "logging"
    DataClass = "confidential" # Flow logs contain IP addresses
  })
}

#--------------------------------------------------------------
# Bucket Configuration — Security Hardening
#--------------------------------------------------------------

# Block ALL public access — log buckets must never be public
resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning — protects against accidental overwrites/deletes
resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with dedicated CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flow_logs_s3.arn
    }
    bucket_key_enabled = true # Reduces KMS API costs by ~99%
  }
}

#--------------------------------------------------------------
# Lifecycle Policy — Cost Optimization
#--------------------------------------------------------------
# Standard → Glacier Flexible Retrieval → Delete
# Glacier FR: $0.0036/GB/month (vs $0.023/GB Standard)
# Suitable for compliance archive (access within 3-5 hours)
#--------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "flow-logs-lifecycle"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    transition {
      days          = var.flow_logs_glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.flow_logs_expiration_days
    }

    # Clean up old versions after 30 days
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

#--------------------------------------------------------------
# Bucket Policy — Allow VPC Flow Logs Delivery
#--------------------------------------------------------------
# VPC Flow Logs (S3 destination) uses delivery.logs.amazonaws.com
# service principal to write log files directly to S3.
# No IAM role needed for S3 destination (unlike CloudWatch).
#--------------------------------------------------------------

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  # Ensure public access block is applied before bucket policy
  depends_on = [aws_s3_bucket_public_access_block.flow_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow Flow Logs service to check bucket ACL
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.flow_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      # Allow Flow Logs service to write log files
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.flow_logs.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      # Enforce encryption in transit
      {
        Sid    = "DenyUnencryptedTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.flow_logs.arn,
          "${aws_s3_bucket.flow_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
