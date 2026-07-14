#--------------------------------------------------------------
# AMG — KMS Customer Managed Key (SSM SecureString encryption)
#--------------------------------------------------------------
# CMK riêng cho SSM SecureString chứa Grafana Service Account Token
# (xem aws_ssm_parameter.service_account_token trong main.tf).
#
# KHÔNG dùng alias/aws/ssm (AWS managed key mặc định) vì key đó cho
# phép MỌI principal trong account có quyền kms:Decrypt chung (không
# thể scope theo policy riêng) decrypt được token admin Grafana.
# CMK cho phép giới hạn đúng principal cần đọc — VD: role chạy
# `terraform apply` trong control-plane/lab-grafana/.
#--------------------------------------------------------------

data "aws_region" "current" {}

resource "aws_kms_key" "amg" {
  description             = "CMK for AMG service account token (SSM SecureString) — ${local.name_prefix}"
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
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow SSM service dùng key để encrypt/decrypt SecureString
      # parameter khi caller (VD: terraform apply trong lab-grafana)
      # có quyền ssm:GetParameter với with_decryption = true.
      {
        Sid    = "AllowSSMService"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-amg-token-cmk"
    Purpose = "amg-token-encryption"
  })
}

# Human-readable alias cho key
resource "aws_kms_alias" "amg" {
  name          = "alias/${local.name_prefix}-amg-token"
  target_key_id = aws_kms_key.amg.key_id
}
