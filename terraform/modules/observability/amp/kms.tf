#--------------------------------------------------------------
# AMP — KMS Customer Managed Key (encryption at-rest)
#--------------------------------------------------------------
# AMP hỗ trợ customer-managed KMS key để mã hóa metrics tại rest.
# Production pattern (giống modules/database/kms.tf): CMK thay vì
# AWS managed key để có:
#   - Key rotation control (auto-rotate hàng năm)
#   - Key policy với IAM/Service constraints rõ ràng
#   - CloudTrail audit (ai dùng key này, khi nào)
#   - Schedule key deletion (7-30 ngày window thay vì xóa ngay)
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "amp" {
  description             = "CMK for AMP workspace encryption at-rest — ${local.name_prefix}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 14
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow account root full access (bắt buộc để quản trị key sau này)
      {
        Sid    = "AllowRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow APS (Amazon Managed Prometheus) service dùng key để encrypt/decrypt
      {
        Sid    = "AllowAMPService"
        Effect = "Allow"
        Principal = {
          Service = "aps.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "aps.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      # 🛡️ FIX: Explicitly allow ECS Task Role to use KMS key.
      # Identity-based policy (IAM delegation via root) wasn't sufficient
      # due to STS assumed-role evaluation quirks. Adding principal directly
      # on the key policy bypasses the delegation chain entirely.
      {
        Sid       = "AllowECSTaskRoleUsage"
        Effect    = "Allow"
        Principal = { AWS = var.ecs_task_role_arn }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-amp-cmk"
    Purpose = "amp-encryption"
  })
}

# Human-readable alias cho key
resource "aws_kms_alias" "amp" {
  name          = "alias/${local.name_prefix}-amp"
  target_key_id = aws_kms_key.amp.key_id
}
