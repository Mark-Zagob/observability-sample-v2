#--------------------------------------------------------------
# Database Module — Contract Tests (Plan Only)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/contract.tftest.hcl
# These tests ONLY run terraform plan — NO AWS resources created.
# Cost: $0.00
# Duration: ~10-15 seconds
#
# Purpose:
#   Validate input variable constraints, default values, and
#   resource configuration logic WITHOUT touching AWS.
#--------------------------------------------------------------

variables {
  project_name           = "test-db"
  environment            = "lab"
  vpc_id                 = "vpc-0123456789abcdef0"
  data_subnet_ids        = ["subnet-aaa111", "subnet-bbb222"]
  data_security_group_id = "sg-0123456789abcdef0"
  common_tags = {
    Environment = "test"
    ManagedBy   = "terraform-test"
  }
}

#--------------------------------------------------------------
# 1. Variable Validation — environment
#--------------------------------------------------------------

run "reject_invalid_environment" {
  command = plan

  variables {
    environment = "invalid"
  }

  expect_failures = [var.environment]
}

run "accept_valid_environment_dev" {
  command = plan

  variables {
    environment = "dev"
  }

  # Should not fail — "dev" is valid
  assert {
    condition     = var.environment == "dev"
    error_message = "Should accept 'dev' as valid environment"
  }
}

run "accept_valid_environment_prod" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = var.environment == "prod"
    error_message = "Should accept 'prod' as valid environment"
  }
}

#--------------------------------------------------------------
# 2. Variable Validation — data_subnet_ids
#--------------------------------------------------------------

run "reject_single_subnet" {
  command = plan

  variables {
    data_subnet_ids = ["subnet-only-one"]
  }

  expect_failures = [var.data_subnet_ids]
}

#--------------------------------------------------------------
# 3. Variable Validation — backup_retention_period
#--------------------------------------------------------------

run "reject_negative_backup_retention" {
  command = plan

  variables {
    backup_retention_period = -1
  }

  expect_failures = [var.backup_retention_period]
}

run "reject_backup_retention_above_35" {
  command = plan

  variables {
    backup_retention_period = 36
  }

  expect_failures = [var.backup_retention_period]
}

#--------------------------------------------------------------
# 4. Variable Validation — enhanced_monitoring_interval
#--------------------------------------------------------------

run "reject_invalid_monitoring_interval" {
  command = plan

  variables {
    enhanced_monitoring_interval = 45
  }

  expect_failures = [var.enhanced_monitoring_interval]
}

#--------------------------------------------------------------
# 5. Default Values — Verify sensible defaults
#--------------------------------------------------------------

run "default_values_are_sensible" {
  command = plan

  assert {
    condition     = var.instance_class == "db.t3.micro"
    error_message = "Default instance_class must be db.t3.micro"
  }

  assert {
    condition     = var.engine_version == "16.4"
    error_message = "Default engine_version must be 16.4"
  }

  assert {
    condition     = var.db_name == "orders"
    error_message = "Default db_name must be 'orders'"
  }

  assert {
    condition     = var.db_username == "dbadmin"
    error_message = "Default db_username must be 'dbadmin'"
  }

  assert {
    condition     = var.multi_az == false
    error_message = "Default multi_az must be false"
  }

  assert {
    condition     = var.backup_retention_period == 1
    error_message = "Default backup_retention_period must be 1"
  }

  assert {
    condition     = var.deletion_protection == false
    error_message = "Default deletion_protection must be false"
  }

  assert {
    condition     = var.skip_final_snapshot == true
    error_message = "Default skip_final_snapshot must be true"
  }

  assert {
    condition     = var.enhanced_monitoring_interval == 0
    error_message = "Default enhanced_monitoring_interval must be 0 (disabled)"
  }

  assert {
    condition     = var.enable_cloudwatch_alarms == true
    error_message = "Default enable_cloudwatch_alarms must be true"
  }

  assert {
    condition     = var.alarm_cpu_threshold == 80
    error_message = "Default alarm_cpu_threshold must be 80"
  }
}

#--------------------------------------------------------------
# 6. RDS Instance Configuration
#--------------------------------------------------------------

run "rds_instance_configured_correctly" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.engine == "postgres"
    error_message = "RDS engine must be postgres"
  }

  assert {
    condition     = aws_db_instance.postgres.engine_version == "16.4"
    error_message = "RDS engine version must be 16.4"
  }

  assert {
    condition     = aws_db_instance.postgres.storage_type == "gp3"
    error_message = "RDS storage type must be gp3"
  }

  assert {
    condition     = aws_db_instance.postgres.storage_encrypted == true
    error_message = "RDS storage must be encrypted at-rest"
  }

  assert {
    condition     = aws_db_instance.postgres.publicly_accessible == false
    error_message = "RDS must NOT be publicly accessible"
  }

  assert {
    condition     = aws_db_instance.postgres.performance_insights_enabled == true
    error_message = "Performance Insights must be enabled"
  }

  assert {
    condition     = aws_db_instance.postgres.iam_database_authentication_enabled == true
    error_message = "IAM database authentication must be enabled"
  }

  assert {
    condition     = aws_db_instance.postgres.copy_tags_to_snapshot == true
    error_message = "Tags must be copied to snapshots"
  }
}

#--------------------------------------------------------------
# 7. Security — Secrets Manager
#--------------------------------------------------------------

run "secrets_manager_configured" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.db_master_password.recovery_window_in_days == 0
    error_message = "Lab environment should have 0-day recovery window"
  }
}

run "secrets_manager_prod_recovery_window" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_secretsmanager_secret.db_master_password.recovery_window_in_days == 30
    error_message = "Prod environment must have 30-day recovery window"
  }
}

#--------------------------------------------------------------
# 8. Random Password Configuration
#--------------------------------------------------------------

run "password_meets_requirements" {
  command = plan

  assert {
    condition     = random_password.db_master.length == 24
    error_message = "Password length must be 24 characters"
  }

  assert {
    condition     = random_password.db_master.special == true
    error_message = "Password must include special characters"
  }
}

#--------------------------------------------------------------
# 9. Parameter Group
#--------------------------------------------------------------

run "parameter_group_family_correct" {
  command = plan

  assert {
    condition     = aws_db_parameter_group.postgres.family == "postgres16"
    error_message = "Parameter group family must be postgres16"
  }
}

#--------------------------------------------------------------
# 10. Monitoring — Conditional Enhanced Monitoring
#--------------------------------------------------------------

run "no_monitoring_role_when_disabled" {
  command = plan

  variables {
    enhanced_monitoring_interval = 0
  }

  assert {
    condition     = length(aws_iam_role.rds_monitoring) == 0
    error_message = "Monitoring IAM role must not be created when interval is 0"
  }
}

run "monitoring_role_created_when_enabled" {
  command = plan

  variables {
    enhanced_monitoring_interval = 60
  }

  assert {
    condition     = length(aws_iam_role.rds_monitoring) == 1
    error_message = "Monitoring IAM role must be created when interval > 0"
  }
}

#--------------------------------------------------------------
# 11. CloudWatch Alarms — Conditional
#--------------------------------------------------------------

run "alarms_created_when_enabled" {
  command = plan

  variables {
    enable_cloudwatch_alarms = true
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1
    error_message = "CPU alarm must be created when alarms enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.storage_low) == 1
    error_message = "Storage alarm must be created when alarms enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.connections_high) == 1
    error_message = "Connections alarm must be created when alarms enabled"
  }
}

run "no_alarms_when_disabled" {
  command = plan

  variables {
    enable_cloudwatch_alarms = false
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 0
    error_message = "CPU alarm must not be created when alarms disabled"
  }
}

#--------------------------------------------------------------
# 12. CloudWatch Log Group
#--------------------------------------------------------------

run "log_group_retention_lab" {
  command = plan

  variables {
    environment = "lab"
  }

  assert {
    condition     = aws_cloudwatch_log_group.rds_postgres.retention_in_days == 14
    error_message = "Lab log retention must be 14 days"
  }
}

run "log_group_retention_prod" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_cloudwatch_log_group.rds_postgres.retention_in_days == 90
    error_message = "Prod log retention must be 90 days"
  }
}

#--------------------------------------------------------------
# 13. SSM Parameters — Count
#--------------------------------------------------------------

run "ssm_parameters_created" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.db_endpoint.type == "String"
    error_message = "SSM db_endpoint must be String type"
  }

  assert {
    condition     = aws_ssm_parameter.db_host.type == "String"
    error_message = "SSM db_host must be String type"
  }

  assert {
    condition     = aws_ssm_parameter.db_port.type == "String"
    error_message = "SSM db_port must be String type"
  }

  assert {
    condition     = aws_ssm_parameter.db_name.type == "String"
    error_message = "SSM db_name must be String type"
  }

  assert {
    condition     = aws_ssm_parameter.db_username.type == "String"
    error_message = "SSM db_username must be String type"
  }

  assert {
    condition     = aws_ssm_parameter.db_secret_arn.type == "String"
    error_message = "SSM db_secret_arn must be String type"
  }
}

#--------------------------------------------------------------
# 14. Naming Convention
#--------------------------------------------------------------

run "resource_naming_convention" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.identifier == "test-db-lab-postgres"
    error_message = "RDS identifier must follow {project}-{env}-postgres pattern"
  }

  assert {
    condition     = aws_db_subnet_group.main.name == "test-db-lab-postgres-subnet-group"
    error_message = "Subnet group name must follow {project}-{env}-postgres-subnet-group pattern"
  }

  assert {
    condition     = aws_db_parameter_group.postgres.name == "test-db-lab-postgres-params"
    error_message = "Parameter group name must follow {project}-{env}-postgres-params pattern"
  }
}
