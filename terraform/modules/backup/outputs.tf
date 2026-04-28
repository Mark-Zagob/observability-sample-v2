#--------------------------------------------------------------
# Backup Module — Outputs
#--------------------------------------------------------------
# Consumed by:
#   - DR module → vault ARNs for cross-region infrastructure
#   - Monitoring → SNS topic for centralized alerting
#   - Other modules → to reference backup plan/vault
#--------------------------------------------------------------

#--------------------------------------------------------------
# Vault
#--------------------------------------------------------------

output "vault_arn" {
  description = "ARN of the primary backup vault"
  value       = aws_backup_vault.primary.arn
}

output "vault_name" {
  description = "Name of the primary backup vault"
  value       = aws_backup_vault.primary.name
}

output "vault_dr_arn" {
  description = "ARN of the DR region backup vault (null if cross-region copy disabled)"
  value       = var.enable_cross_region_copy ? aws_backup_vault.dr[0].arn : null
}

#--------------------------------------------------------------
# Plan
#--------------------------------------------------------------

output "plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.main.id
}

output "plan_arn" {
  description = "ARN of the backup plan"
  value       = aws_backup_plan.main.arn
}

#--------------------------------------------------------------
# IAM
#--------------------------------------------------------------

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup"
  value       = aws_iam_role.backup.arn
}

#--------------------------------------------------------------
# KMS
#--------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS CMK for primary vault encryption"
  value       = aws_kms_key.backup.arn
}

output "kms_key_dr_arn" {
  description = "ARN of the KMS CMK for DR vault encryption (null if disabled)"
  value       = var.enable_cross_region_copy ? aws_kms_key.backup_dr[0].arn : null
}

#--------------------------------------------------------------
# Notifications
#--------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for backup notifications (reusable for other modules)"
  value       = aws_sns_topic.backup.arn
}

#--------------------------------------------------------------
# Selection
#--------------------------------------------------------------

output "selection_tag" {
  description = "Tag key/value pair used for backup selection (add this tag to resources to protect them)"
  value = {
    key   = var.selection_tag_key
    value = var.selection_tag_value
  }
}

#--------------------------------------------------------------
# Reporting
#--------------------------------------------------------------

output "report_plan_arn" {
  description = "ARN of the backup compliance report plan (null if disabled)"
  value       = var.enable_backup_reports ? aws_backup_report_plan.compliance[0].arn : null
}

output "report_bucket_name" {
  description = "S3 bucket name for backup compliance reports (null if disabled)"
  value       = var.enable_backup_reports ? aws_s3_bucket.backup_reports[0].id : null
}
