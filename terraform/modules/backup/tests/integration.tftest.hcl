#--------------------------------------------------------------
# Backup Module — Integration Tests (Apply + Destroy)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/integration.tftest.hcl
# These tests APPLY real AWS resources and then DESTROY them.
#
# Cost:  ~$0.10 per run (Backup vault + KMS key, no actual
#        backup jobs triggered during test)
# Duration: ~3-5 minutes (KMS + Backup vault creation)
#
# Prerequisites:
#   - Valid AWS credentials configured
#   - Permissions: KMS, AWS Backup, IAM, SNS, CloudWatch
#   - DR region (ap-southeast-1) accessible
#--------------------------------------------------------------

#--------------------------------------------------------------
# Shared test variables
#--------------------------------------------------------------

variables {
  project_name = "inttest-bkp"
  environment  = "lab"
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

# ============================================================
# 1. Vault — Core Creation (no DR)
#    Validates: vault created with KMS encryption
# ============================================================

run "vault_created_with_encryption" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 7
    enable_cloudwatch_alarms = false
  }

  # Vault name follows convention
  assert {
    condition     = aws_backup_vault.primary.name == "inttest-bkp-lab-backup-vault"
    error_message = "Vault name must follow {project}-{env}-backup-vault pattern"
  }

  # KMS key is attached
  assert {
    condition     = aws_backup_vault.primary.kms_key_arn != ""
    error_message = "Vault must be encrypted with KMS CMK"
  }

  # KMS key rotation is enabled
  assert {
    condition     = aws_kms_key.backup.enable_key_rotation == true
    error_message = "KMS key must have rotation enabled"
  }

  # No DR vault created
  assert {
    condition     = length(aws_backup_vault.dr) == 0
    error_message = "DR vault must not exist when cross-region copy is disabled"
  }
}

# ============================================================
# 2. Vault Lock — Protection Applied
#    Validates: vault lock exists with correct retention bounds
# ============================================================

run "vault_lock_applied" {
  command = apply

  variables {
    enable_cross_region_copy      = false
    enable_monthly_plan           = false
    daily_retention_days          = 7
    vault_lock_min_retention_days = 1
    vault_lock_max_retention_days = 365
    enable_cloudwatch_alarms      = false
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.primary.min_retention_days == 1
    error_message = "Vault lock min_retention_days must be 1"
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.primary.max_retention_days == 365
    error_message = "Vault lock max_retention_days must be 365"
  }
}

# ============================================================
# 3. Backup Plan — Daily Rule Created
#    Validates: plan and daily rule exist with correct config
# ============================================================

run "backup_plan_daily_rule" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 14
    daily_schedule           = "cron(0 4 * * ? *)"
    daily_start_window       = 120
    daily_completion_window  = 360
    enable_cloudwatch_alarms = false
  }

  # Plan name follows convention
  assert {
    condition     = aws_backup_plan.main.name == "inttest-bkp-lab-backup-plan"
    error_message = "Plan name must follow naming convention"
  }

  # Daily rule has correct schedule
  assert {
    condition     = aws_backup_plan.main.rule[0].schedule == "cron(0 4 * * ? *)"
    error_message = "Daily rule must use configured schedule"
  }

  # Start window uses variable (not hardcoded)
  assert {
    condition     = aws_backup_plan.main.rule[0].start_window == 120
    error_message = "Start window must use configured value (120), not hardcoded 60"
  }

  # Completion window uses variable (not hardcoded)
  assert {
    condition     = aws_backup_plan.main.rule[0].completion_window == 360
    error_message = "Completion window must use configured value (360), not hardcoded 180"
  }
}

# ============================================================
# 4. IAM Role — Correct Policies Attached
#    Validates: role exists and can be assumed by backup service
# ============================================================

run "iam_role_created" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 7
    enable_cloudwatch_alarms = false
  }

  # Role name follows convention
  assert {
    condition     = aws_iam_role.backup.name == "inttest-bkp-lab-backup-role"
    error_message = "IAM role name must follow naming convention"
  }

  # At least 4 policy attachments exist
  assert {
    condition     = length(aws_iam_role_policy_attachment.backup_service) > 0
    error_message = "Backup service policy must be attached"
  }
}

# ============================================================
# 5. SNS Topic — Encrypted and Notifications Configured
#    Validates: SNS topic uses KMS, vault notifications set
# ============================================================

run "sns_topic_encrypted" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 7
    enable_cloudwatch_alarms = false
  }

  # SNS topic uses KMS
  assert {
    condition     = aws_sns_topic.backup.kms_master_key_id != ""
    error_message = "SNS topic must be KMS encrypted"
  }

  # Vault notifications reference correct vault
  assert {
    condition     = aws_backup_vault_notifications.primary.backup_vault_name == aws_backup_vault.primary.name
    error_message = "Vault notifications must reference primary vault"
  }
}

# ============================================================
# 6. Selection — Tag-Based Discovery
#    Validates: selection uses correct tag
# ============================================================

run "selection_uses_tags" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 7
    selection_tag_key        = "BackupTest"
    selection_tag_value      = "yes"
    enable_cloudwatch_alarms = false
  }

  assert {
    condition     = aws_backup_selection.tagged_resources.selection_tag[0].key == "BackupTest"
    error_message = "Selection must use configured tag key"
  }

  assert {
    condition     = aws_backup_selection.tagged_resources.selection_tag[0].value == "yes"
    error_message = "Selection must use configured tag value"
  }
}

# ============================================================
# 7. Output Contract — ARNs Valid
#    Validates: outputs have correct ARN format
# ============================================================

run "output_arns_valid" {
  command = apply

  variables {
    enable_cross_region_copy = false
    enable_monthly_plan      = false
    daily_retention_days     = 7
    enable_cloudwatch_alarms = false
  }

  # Vault ARN valid
  assert {
    condition     = can(regex("^arn:aws:backup:", output.vault_arn))
    error_message = "Vault ARN must be valid backup ARN"
  }

  # Plan ARN valid
  assert {
    condition     = can(regex("^arn:aws:backup:", output.plan_arn))
    error_message = "Plan ARN must be valid backup ARN"
  }

  # KMS key ARN valid
  assert {
    condition     = can(regex("^arn:aws:kms:", output.kms_key_arn))
    error_message = "KMS key ARN must be valid KMS ARN"
  }

  # SNS topic ARN valid
  assert {
    condition     = can(regex("^arn:aws:sns:", output.sns_topic_arn))
    error_message = "SNS topic ARN must be valid SNS ARN"
  }

  # DR vault should be null
  assert {
    condition     = output.vault_dr_arn == null
    error_message = "DR vault ARN must be null when cross-region disabled"
  }

  # Selection tag output
  assert {
    condition     = output.selection_tag.key == "Backup"
    error_message = "Selection tag key must default to 'Backup'"
  }
}
