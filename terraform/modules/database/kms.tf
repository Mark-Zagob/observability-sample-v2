#--------------------------------------------------------------
# Database Module — KMS Customer Managed Key
#--------------------------------------------------------------
# Production pattern: CMK instead of AWS managed key.
# Benefits:
#   - Key rotation control (auto-rotate annually)
#   - Key policy with IAM constraints
#   - CloudTrail audit (who used this key, when)
#   - Cross-account access for shared snapshots
#   - Schedule key deletion (7-30 day window)
#--------------------------------------------------------------

resource "aws_kms_key" "rds" {
  description             = "CMK for RDS encryption at-rest — ${local.identifier}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  # Key policy: restrict to this account + RDS service
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow account root full access (required for key administration)
      {
        Sid    = "AllowRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow RDS service to use the key for encryption/decryption
      {
        Sid    = "AllowRDSService"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "rds.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      # Allow CloudWatch/Performance Insights to use the key
      {
        Sid    = "AllowCloudWatchPerformanceInsights"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-cmk"
    Component = "database"
    Purpose   = "rds-encryption"
  })
}

# Human-readable alias for the key
resource "aws_kms_alias" "rds" {
  name          = "alias/${local.identifier}"
  target_key_id = aws_kms_key.rds.key_id
}
