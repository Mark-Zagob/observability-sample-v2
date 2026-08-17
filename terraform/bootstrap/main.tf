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

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "state-key-policy"
    Statement = concat(
      # 1. Root Account - Luôn luôn có (Hardcoded)
      [
        {
          Sid       = "Enable IAM User Permissions"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        }
      ],
      
      # 2. Key Administrators - Chỉ thêm vào NẾU list không rỗng
      length(var.key_administrator_arns) > 0 ? [
        {
          Sid       = "Allow Key Administration"
          Effect    = "Allow"
          Principal = { AWS = var.key_administrator_arns }
          Action = [
            "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
            "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
            "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource"
          ]
          Resource = "*"
        }
      ] : [], # Nếu rỗng thì trả về list rỗng, concat sẽ tự động bỏ qua

      # 3. Key Users - Chỉ thêm vào NẾU list không rỗng
      length(var.key_user_arns) > 0 ? [
        {
          Sid       = "Allow Key Usage for State"
          Effect    = "Allow"
          Principal = { AWS = var.key_user_arns }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey",
            "kms:DescribeKey"
          ]
          Resource = "*"
        }
      ] : []
    )
  })
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn  # ← Reuse CMK
    }
    bucket_key_enabled = true  # ← Reduce KMS API calls
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
  object_lock_enabled = true # 🛡️ CRITICAL: Enable WORM (Write Once, Read Many) at creation
  force_destroy = true
  tags = {
    Name    = local.bucket_name
    Purpose = "terraform-state"
  }

  # Prevent accidental deletion of the state bucket
  # lifecycle {
  #   prevent_destroy = true
  # }
}

#🛡️ Object Lock Configuration (Governance Mode)
#Ngăn chặn Ransomware hoặc Insider xóa state file trong 30 ngày.
resource "aws_s3_bucket_object_lock_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    default_retention {
      mode = "GOVERNANCE" # Governance cho phép Root bypass nếu có header đặc biệt. COMPLIANCE thì Root cũng bó tay.
      days = 30
    }
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

  depends_on = [aws_s3_bucket_object_lock_configuration.state]
  rule {
    id     = "cleanup-old-state-versions"
    status = "Enabled"

    filter {}

    # Sau 30 ngày, chuyển state cũ sang Glacier Instant Retrieval (Rẻ hơn 60%)
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER_IR"
    }

    # Xóa hẳn sau 90 ngày
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
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn # Dùng chung KMS CMK cho đồng bộ
  }

  # 🛡️ CRITICAL: Prevent accidental deletion via `terraform destroy`
  deletion_protection_enabled = true 

  tags = {
    Name    = var.dynamodb_table_name
    Purpose = "terraform-state-locking"
  }
}


#--------------------------------------------------------------
# 5. Real-Time Alerting (EventBridge + SNS)
#--------------------------------------------------------------
# Alert ngay lập tức nếu có ai đó cố tình xóa State Bucket
resource "aws_sns_topic" "state_alerts" {
  name = "${var.project_name}-state-security-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.state_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # Thêm var này vào variables.tf
}

resource "aws_cloudwatch_event_rule" "state_bucket_deletion" {
  name        = "${var.project_name}-state-bucket-deletion-attempt"
  description = "Alerts when someone tries to delete the state bucket or change its policy"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["DeleteBucket", "PutBucketPolicy", "PutBucketAcl"]
      requestParameters = {
        bucketName = [aws_s3_bucket.state.id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.state_bucket_deletion.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.state_alerts.arn
}