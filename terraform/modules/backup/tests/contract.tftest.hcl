#--------------------------------------------------------------
# Backup Module — Contract Tests
#--------------------------------------------------------------
# Validates variable constraints and default behaviors.
# Run: terraform test (from module directory)
#--------------------------------------------------------------

# ============================================================
# Provider mock — required for plan-only tests
# ============================================================
mock_provider "aws" {}
mock_provider "aws" {
  alias = "dr"
}

# ============================================================
# Test: Default values produce valid configuration
# ============================================================
run "defaults_are_valid" {
  command = plan

  variables {
    project_name = "test-project"
    environment  = "lab"
  }

  # Vault exists
  assert {
    condition     = aws_backup_vault.primary.name == "test-project-lab-backup-vault"
    error_message = "Expected vault name 'test-project-lab-backup-vault'"
  }

  # KMS key has rotation enabled
  assert {
    condition     = aws_kms_key.backup.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled"
  }

  # Default daily retention = 35
  assert {
    condition     = aws_backup_plan.main.rule[0].lifecycle[0].delete_after == 35
    error_message = "Default daily retention should be 35 days"
  }
}

# ============================================================
# Test: Invalid environment rejected
# ============================================================
run "invalid_environment_rejected" {
  command = plan

  variables {
    project_name = "test-project"
    environment  = "invalid"
  }

  expect_failures = [
    var.environment,
  ]
}

# ============================================================
# Test: Invalid vault lock mode rejected
# ============================================================
run "invalid_vault_lock_mode_rejected" {
  command = plan

  variables {
    project_name    = "test-project"
    vault_lock_mode = "invalid"
  }

  expect_failures = [
    var.vault_lock_mode,
  ]
}

# ============================================================
# Test: Daily retention validation (minimum)
# ============================================================
run "daily_retention_too_low_rejected" {
  command = plan

  variables {
    project_name         = "test-project"
    daily_retention_days = 0
  }

  expect_failures = [
    var.daily_retention_days,
  ]
}

# ============================================================
# Test: Cross-region disabled — no DR resources
# ============================================================
run "cross_region_disabled" {
  command = plan

  variables {
    project_name             = "test-project"
    enable_cross_region_copy = false
  }

  # DR vault should not exist
  assert {
    condition     = length(aws_backup_vault.dr) == 0
    error_message = "DR vault should not be created when cross-region copy is disabled"
  }

  # DR KMS key should not exist
  assert {
    condition     = length(aws_kms_key.backup_dr) == 0
    error_message = "DR KMS key should not be created when cross-region copy is disabled"
  }
}

# ============================================================
# Test: Vault lock changeable_days validation
# ============================================================
run "vault_lock_changeable_days_too_low_rejected" {
  command = plan

  variables {
    project_name                = "test-project"
    vault_lock_changeable_days = 1
  }

  expect_failures = [
    var.vault_lock_changeable_days,
  ]
}
