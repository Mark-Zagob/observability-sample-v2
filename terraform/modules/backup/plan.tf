#--------------------------------------------------------------
# Backup Module — Plan & Selection
#--------------------------------------------------------------
# Backup plan defines WHEN and HOW LONG to keep backups.
# Selection defines WHICH resources to back up.
#
# Reference: AWS Well-Architected REL09-BP01
#--------------------------------------------------------------

########################################################################
# Backup Plan — Daily + Monthly
########################################################################
# Two rules in one plan:
#   Rule 1 (daily):   every day at 3AM, keep 35 days
#   Rule 2 (monthly): 1st of month, keep 365 days, cold storage after 30d
#
# Cross-region copy: attached to daily rule (copies every daily backup
# to DR region vault).
########################################################################

resource "aws_backup_plan" "main" {
  name = "${local.identifier}-plan"

  # Validate retention fits within vault lock bounds
  lifecycle {
    precondition {
      condition     = var.daily_retention_days <= var.vault_lock_max_retention_days
      error_message = "daily_retention_days (${var.daily_retention_days}) must be <= vault_lock_max_retention_days (${var.vault_lock_max_retention_days})."
    }
    precondition {
      condition     = !var.enable_monthly_plan || var.monthly_retention_days <= var.vault_lock_max_retention_days
      error_message = "monthly_retention_days (${var.monthly_retention_days}) must be <= vault_lock_max_retention_days (${var.vault_lock_max_retention_days})."
    }
    # AWS enforces minimum 90 days in cold storage.
    # If cold_storage_after is enabled, retention must be >= cold_storage_after + 90.
    precondition {
      condition     = var.daily_cold_storage_after_days == 0 || var.daily_retention_days >= (var.daily_cold_storage_after_days + 90)
      error_message = "daily_retention_days (${var.daily_retention_days}) must be >= daily_cold_storage_after_days (${var.daily_cold_storage_after_days}) + 90 days (AWS cold storage minimum)."
    }
    precondition {
      condition     = !var.enable_monthly_plan || var.monthly_cold_storage_after_days == 0 || var.monthly_retention_days >= (var.monthly_cold_storage_after_days + 90)
      error_message = "monthly_retention_days (${var.monthly_retention_days}) must be >= monthly_cold_storage_after_days (${var.monthly_cold_storage_after_days}) + 90 days (AWS cold storage minimum)."
    }
  }

  # --- Rule 1: Daily Backup ---
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.daily_schedule
    start_window      = var.daily_start_window
    completion_window = var.daily_completion_window

    lifecycle {
      delete_after       = var.daily_retention_days
      cold_storage_after = var.daily_cold_storage_after_days > 0 ? var.daily_cold_storage_after_days : null
    }

    # Cross-region copy (DR Tier 1 foundation)
    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []

      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn

        lifecycle {
          delete_after = var.cross_region_copy_retention_days
        }
      }
    }
  }

  # --- Rule 2: Monthly Backup (long-term retention) ---
  dynamic "rule" {
    for_each = var.enable_monthly_plan ? [1] : []

    content {
      rule_name         = "monthly-backup"
      target_vault_name = aws_backup_vault.primary.name
      schedule          = var.monthly_schedule
      start_window      = var.monthly_start_window
      completion_window = var.monthly_completion_window

      lifecycle {
        delete_after       = var.monthly_retention_days
        cold_storage_after = var.monthly_cold_storage_after_days > 0 ? var.monthly_cold_storage_after_days : null
      }
    }
  }

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-plan"
    Component = "backup"
  })
}


########################################################################
# Backup Selection — Tag-Based Auto-Discovery
########################################################################
# Resources with tag Backup=true are automatically protected.
# When you add a new RDS or EFS with this tag, AWS Backup
# picks it up without Terraform changes.
#
# This is the recommended production pattern over ARN-based
# selection, which requires updating Terraform for each new resource.
########################################################################

resource "aws_backup_selection" "tagged_resources" {
  name         = "${local.identifier}-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.main.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.selection_tag_key
    value = var.selection_tag_value
  }
}
