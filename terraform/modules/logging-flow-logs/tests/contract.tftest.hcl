#--------------------------------------------------------------
# Logging Module — Contract Tests
#--------------------------------------------------------------
# Validates variable constraints, resource defaults, and
# security controls at plan time (no real AWS resources).
# Run: terraform test (from module directory)
#--------------------------------------------------------------

# ============================================================
# Provider mock — required for plan-only tests
# ============================================================
mock_provider "aws" {}

# ============================================================
# Test: Default values produce valid configuration
# ============================================================
run "defaults_are_valid" {
  command = plan

  variables {
    project_name = "test-project"
    environment  = "lab"
  }

  # S3 bucket exists with correct naming
  assert {
    condition     = aws_s3_bucket.flow_logs.bucket == "test-project-flow-logs-${data.aws_caller_identity.current.account_id}"
    error_message = "Bucket name should follow pattern: {project}-flow-logs-{account_id}"
  }

  # KMS key has rotation enabled
  assert {
    condition     = aws_kms_key.flow_logs_s3.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled"
  }

  # KMS deletion window >= 14 days
  assert {
    condition     = aws_kms_key.flow_logs_s3.deletion_window_in_days >= 14
    error_message = "KMS deletion window must be >= 14 days"
  }

  # S3 public access block — all 4 settings enabled
  assert {
    condition     = aws_s3_bucket_public_access_block.flow_logs.block_public_acls == true
    error_message = "block_public_acls must be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.flow_logs.block_public_policy == true
    error_message = "block_public_policy must be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.flow_logs.ignore_public_acls == true
    error_message = "ignore_public_acls must be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.flow_logs.restrict_public_buckets == true
    error_message = "restrict_public_buckets must be true"
  }

  # S3 versioning enabled
  assert {
    condition     = aws_s3_bucket_versioning.flow_logs.versioning_configuration[0].status == "Enabled"
    error_message = "S3 versioning must be Enabled"
  }

  # S3 encryption uses KMS (not AES256)
  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.flow_logs.rule :
      anytrue([for d in rule.apply_server_side_encryption_by_default : d.sse_algorithm == "aws:kms"])
    ])
    error_message = "S3 must use SSE-KMS encryption"
  }

  # Bucket key enabled for cost reduction
  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.flow_logs.rule :
      rule.bucket_key_enabled == true
    ])
    error_message = "Bucket key must be enabled to reduce KMS API costs"
  }

  # Athena workgroup exists with correct name
  assert {
    condition     = aws_athena_workgroup.flow_logs.name == "test-project-flow-logs"
    error_message = "Athena workgroup name should be 'test-project-flow-logs'"
  }

  # Athena workgroup enforces configuration
  assert {
    condition     = aws_athena_workgroup.flow_logs.configuration[0].enforce_workgroup_configuration == true
    error_message = "Athena workgroup must enforce configuration"
  }

  # Glue database name replaces hyphens with underscores
  assert {
    condition     = aws_glue_catalog_database.flow_logs.name == "test_project_flow_logs"
    error_message = "Glue database name should replace hyphens with underscores"
  }

  # Glue table has partition projection enabled
  assert {
    condition     = aws_glue_catalog_table.flow_logs.parameters["projection.enabled"] == "true"
    error_message = "Partition projection must be enabled"
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
# Test: Glacier transition too low rejected (min 30 days)
# ============================================================
run "glacier_transition_too_low_rejected" {
  command = plan

  variables {
    project_name                      = "test-project"
    flow_logs_glacier_transition_days = 15
  }

  expect_failures = [
    var.flow_logs_glacier_transition_days,
  ]
}

# ============================================================
# Test: Expiration too low rejected (min 90 days)
# ============================================================
run "expiration_too_low_rejected" {
  command = plan

  variables {
    project_name              = "test-project"
    flow_logs_expiration_days = 30
  }

  expect_failures = [
    var.flow_logs_expiration_days,
  ]
}

# ============================================================
# Test: Invalid project_name rejected (uppercase)
# ============================================================
run "invalid_project_name_rejected" {
  command = plan

  variables {
    project_name = "Test_Project"
  }

  expect_failures = [
    var.project_name,
  ]
}

# ============================================================
# Test: HIPAA retention (6 years) accepted
# ============================================================
run "hipaa_retention_accepted" {
  command = plan

  variables {
    project_name              = "test-project"
    flow_logs_expiration_days = 2190 # 6 years
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.flow_logs.rule :
      anytrue([for exp in rule.expiration : exp.days == 2190])
    ])
    error_message = "Should accept 2190-day (6 year) retention for HIPAA"
  }
}
