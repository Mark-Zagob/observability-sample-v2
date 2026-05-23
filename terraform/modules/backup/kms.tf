#--------------------------------------------------------------
# Backup Module — KMS Encryption
#--------------------------------------------------------------
# Dedicated CMK for backup vault encryption.
# Separate from RDS KMS key — defense-in-depth:
# compromising one key doesn't expose backups.
#
# Reference: AWS Well-Architected SEC08-BP01
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  identifier = "${var.project_name}-${var.environment}-backup"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

#--------------------------------------------------------------
# KMS Key — Primary Region Vault
#--------------------------------------------------------------
resource "aws_kms_key" "backup" {
  description             = "CMK for AWS Backup vault encryption — ${local.identifier}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowBackupServiceEncryptDecrypt"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
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
            "kms:ViaService" = "backup.${local.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-kms"
    Component = "backup"
  })
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.identifier}"
  target_key_id = aws_kms_key.backup.key_id
}

#--------------------------------------------------------------
# KMS Key — DR Region Vault
# Only created when cross-region copy is enabled.
# The DR vault needs its own KMS key in the DR region.
#--------------------------------------------------------------
resource "aws_kms_key" "backup_dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  description             = "CMK for AWS Backup DR vault — ${local.identifier}-dr"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Must match primary key policy — AWS Backup needs encrypt/decrypt
  # to write and read recovery points in the DR vault.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowBackupServiceEncryptDecrypt"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
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
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-dr-kms"
    Component = "backup"
    Purpose   = "disaster-recovery"
  })
}

resource "aws_kms_alias" "backup_dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name          = "alias/${local.identifier}-dr"
  target_key_id = aws_kms_key.backup_dr[0].key_id
}
