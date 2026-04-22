#--------------------------------------------------------------
# Bootstrap — Terraform State Infrastructure
#--------------------------------------------------------------
# Resources created:
#   1. KMS CMK for state encryption
#   2. S3 bucket for state storage (versioned, encrypted, logged)
#   3. S3 bucket for access logs
#   4. DynamoDB table for state locking
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_name}-terraform-state-${local.account_id}"
  log_bucket  = "${local.bucket_name}-access-logs"
}

#--------------------------------------------------------------
# 1. KMS Key — Encrypt state at-rest
#--------------------------------------------------------------
# State files contain secrets (passwords, ARNs, endpoints).
# SSE-S3 encrypts but AWS manages the key.
# SSE-KMS with CMK = you control who can decrypt.
#--------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "CMK for Terraform state encryption — ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Key policy: only this account can use the key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-terraform-state-cmk"
    Purpose = "state-encryption"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

#--------------------------------------------------------------
# 2. S3 Bucket — Access Logs (log bucket for the state bucket)
#--------------------------------------------------------------
# Production pattern: state bucket access is audited.
# Who read state? When? From what IP? → S3 access logs.
#--------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  bucket = local.log_bucket

  tags = {
    Name    = local.log_bucket
    Purpose = "state-access-logs"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Log bucket uses SSE-S3 (simpler)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

#--------------------------------------------------------------
# 3. S3 Bucket — Terraform State
#--------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    Name    = local.bucket_name
    Purpose = "terraform-state"
  }

  # Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning — rollback to previous state if needed
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption — KMS CMK for state at-rest
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true # Reduce KMS API calls
  }
}

# Block ALL public access — state should NEVER be public
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Access logging — audit who reads/writes state
resource "aws_s3_bucket_logging" "state" {
  bucket = aws_s3_bucket.state.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "state-access-logs/"
}

# Lifecycle — cleanup old state versions
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "cleanup-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_retention_days
    }
  }
}

# Bucket policy — enforce encryption + HTTPS only
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Deny unencrypted uploads
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.state.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      # Deny HTTP (non-SSL) requests
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*"
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

#--------------------------------------------------------------
# 4. DynamoDB Table — State Locking
#--------------------------------------------------------------
# Prevents concurrent terraform apply from corrupting state.
# Uses on-demand billing — cost nearly $0 for this use case.
#--------------------------------------------------------------
resource "aws_dynamodb_table" "locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand — no capacity planning

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-Time Recovery — restore lock table if corrupted
  point_in_time_recovery {
    enabled = true
  }

  # Encrypt with default AWS key (sufficient for lock metadata)
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name    = var.dynamodb_table_name
    Purpose = "terraform-state-locking"
  }
}
