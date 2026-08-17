#--------------------------------------------------------------
# Backup Module — Vault, Lock, Access Policy
#--------------------------------------------------------------
# Centralized AWS Backup vaults (primary + DR).
#
# Architecture:
#   Vault (primary) ← daily + monthly backup plans
#   Vault (DR)      ← cross-region copy destination
#
# Reference: AWS Well-Architected REL09-BP02, REL09-BP03
#--------------------------------------------------------------

########################################################################
# 1. Backup Vault — Primary Region
########################################################################
# Vault = container for recovery points (backup snapshots).
# Encrypted with dedicated CMK (separate from RDS key).
########################################################################

resource "aws_backup_vault" "primary" {
  name        = "${local.identifier}-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-vault"
    Component = "backup"
  })
}

#--------------------------------------------------------------
# Vault Lock — Prevent accidental/malicious deletion
#--------------------------------------------------------------
# Governance mode: IAM policies can bypass (for lab flexibility).
# Compliance mode: nobody can delete, even root (for regulated envs).
#
# min/max_retention enforce that backup plans can only create
# recovery points within allowed retention windows.
#--------------------------------------------------------------
resource "aws_backup_vault_lock_configuration" "primary" {
  backup_vault_name = aws_backup_vault.primary.name

  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_mode == "compliance" ? var.vault_lock_changeable_days : null
}

#--------------------------------------------------------------
# Vault Access Policy — Defense-in-Depth
#--------------------------------------------------------------
# Deny recovery point deletion from anyone except the backup
# service role itself. This prevents a compromised IAM user
# from deleting backups even if they have iam:* permissions.
#--------------------------------------------------------------
resource "aws_backup_vault_policy" "primary" {
  backup_vault_name = aws_backup_vault.primary.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDeleteRecoveryPoints"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "backup:DeleteRecoveryPoint",
          "backup:UpdateRecoveryPointLifecycle"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = aws_iam_role.backup.arn
          }
        }
      }
    ]
  })
}


########################################################################
# 2. Backup Vault — DR Region (cross-region copy destination)
########################################################################

resource "aws_backup_vault" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name        = "${local.identifier}-vault-dr"
  kms_key_arn = aws_kms_key.backup_dr[0].arn

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-vault-dr"
    Component = "backup"
    Purpose   = "disaster-recovery"
  })
}

#--------------------------------------------------------------
# DR Vault Lock — same protection as primary
#--------------------------------------------------------------
resource "aws_backup_vault_lock_configuration" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  backup_vault_name = aws_backup_vault.dr[0].name

  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_mode == "compliance" ? var.vault_lock_changeable_days : null
}

#--------------------------------------------------------------
# DR Vault Access Policy — deny delete (same as primary)
#--------------------------------------------------------------
resource "aws_backup_vault_policy" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  backup_vault_name = aws_backup_vault.dr[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDeleteRecoveryPoints"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "backup:DeleteRecoveryPoint",
          "backup:UpdateRecoveryPointLifecycle"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = aws_iam_role.backup.arn
          }
        }
      }
    ]
  })
}
