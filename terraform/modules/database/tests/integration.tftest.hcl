#--------------------------------------------------------------
# Database Module — Integration Tests (Apply + Destroy)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/integration.tftest.hcl
# These tests APPLY real AWS resources and then DESTROY them.
#
# Cost:  ~$0.50-1.00 per run (RDS db.t3.micro ~$0.02/hr,
#        Secrets Manager ~$0.40/secret/month prorated,
#        test duration ~15-20 min including RDS creation)
# Duration: ~15-20 minutes (RDS provisioning is the bottleneck)
#
# Prerequisites:
#   - Valid AWS credentials configured
#   - Permissions: VPC, Subnets, Security Groups, RDS, Secrets
#     Manager, SSM Parameter Store, CloudWatch, IAM
#
# IMPORTANT — RDS Creation Time:
#   RDS db.t3.micro takes ~8-12 minutes to provision.
#   Test 2 (the first apply of the database module) will be slow.
#   Subsequent tests reuse the same state and are fast.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Setup: Create test VPC + Subnets + Security Group
#--------------------------------------------------------------

run "setup_infrastructure" {
  command = apply

  module {
    source = "./tests/setup"
  }

  variables {
    project_name = "inttest-db"
  }
}

#--------------------------------------------------------------
# Shared test variables
#--------------------------------------------------------------

variables {
  project_name = "inttest-db"
  environment  = "lab"
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# 1. RDS Instance — Core Creation
#    Validates: RDS created with correct engine, encryption,
#    and returns valid endpoint
#--------------------------------------------------------------

run "rds_instance_created_successfully" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id

    # Use smallest config for fast testing
    instance_class        = "db.t3.micro"
    allocated_storage     = 20
    max_allocated_storage = 30

    # Lab settings — fast teardown
    multi_az                = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true

    # Disable Enhanced Monitoring (avoid IAM delay)
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # Endpoint must be valid
  assert {
    condition     = can(regex("^inttest-db-lab-postgres\\.", output.rds_endpoint))
    error_message = "RDS endpoint must start with instance identifier"
  }

  assert {
    condition     = output.rds_port == 5432
    error_message = "RDS port must be 5432"
  }

  assert {
    condition     = output.rds_db_name == "orders"
    error_message = "RDS database name must be 'orders'"
  }

  assert {
    condition     = output.rds_instance_id == "inttest-db-lab-postgres"
    error_message = "RDS instance ID must follow naming convention"
  }
}

#--------------------------------------------------------------
# 2. Secrets Manager — Password Stored Correctly
#    Senior security: verify secret exists and has valid ARN
#--------------------------------------------------------------

run "secret_created_in_secrets_manager" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # Secret ARN must be valid
  assert {
    condition     = can(regex("^arn:aws:secretsmanager:", output.db_secret_arn))
    error_message = "Secret ARN must be valid Secrets Manager ARN"
  }

  # Secret name must follow convention
  assert {
    condition     = output.db_secret_name == "inttest-db/lab/database/master-password"
    error_message = "Secret name must follow {project}/{env}/database/master-password pattern"
  }
}

#--------------------------------------------------------------
# 3. RDS Instance — Security Properties
#    Validates encryption, no public access, IAM auth
#--------------------------------------------------------------

run "rds_security_properties_correct" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # Storage encryption must be enabled
  assert {
    condition     = aws_db_instance.postgres.storage_encrypted == true
    error_message = "RDS storage must be encrypted at-rest"
  }

  # Must NOT be publicly accessible
  assert {
    condition     = aws_db_instance.postgres.publicly_accessible == false
    error_message = "RDS must not be publicly accessible"
  }

  # IAM auth must be enabled
  assert {
    condition     = aws_db_instance.postgres.iam_database_authentication_enabled == true
    error_message = "IAM database authentication must be enabled"
  }

  # Performance Insights must be enabled
  assert {
    condition     = aws_db_instance.postgres.performance_insights_enabled == true
    error_message = "Performance Insights must be enabled"
  }
}

#--------------------------------------------------------------
# 4. SSM Parameters — Endpoint Discovery
#    Validates parameters created with correct values
#--------------------------------------------------------------

run "ssm_parameters_created_with_values" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # SSM parameter ARNs map must have all keys
  assert {
    condition     = length(output.ssm_parameter_arns) == 6
    error_message = "SSM parameter ARNs map must have 6 entries"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "endpoint")
    error_message = "SSM parameters must include 'endpoint'"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "host")
    error_message = "SSM parameters must include 'host'"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "port")
    error_message = "SSM parameters must include 'port'"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "name")
    error_message = "SSM parameters must include 'name'"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "username")
    error_message = "SSM parameters must include 'username'"
  }

  assert {
    condition     = contains(keys(output.ssm_parameter_arns), "secret_arn")
    error_message = "SSM parameters must include 'secret_arn'"
  }

  # SSM prefix must be correct
  assert {
    condition     = output.ssm_parameter_prefix == "/inttest-db/lab/database"
    error_message = "SSM parameter prefix must follow /{project}/{env}/database pattern"
  }

  # All ARNs must be valid
  assert {
    condition     = can(regex("^arn:aws:ssm:", output.ssm_parameter_arns["endpoint"]))
    error_message = "SSM endpoint parameter ARN must be valid"
  }
}

#--------------------------------------------------------------
# 5. CloudWatch — Log Group + Alarms
#--------------------------------------------------------------

run "cloudwatch_resources_created" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # Log group must exist
  assert {
    condition     = can(regex("/aws/rds/instance/inttest-db-lab-postgres/postgresql", output.cloudwatch_log_group_name))
    error_message = "CloudWatch log group name must follow RDS naming convention"
  }

  # Alarms must exist (enable_cloudwatch_alarms = true)
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

#--------------------------------------------------------------
# 6. Tags — Verify on Real Resources
#--------------------------------------------------------------

run "tags_applied_to_rds_instance" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  assert {
    condition     = aws_db_instance.postgres.tags["Component"] == "database"
    error_message = "RDS must have Component=database tag"
  }

  assert {
    condition     = aws_db_instance.postgres.tags["Engine"] == "postgres"
    error_message = "RDS must have Engine=postgres tag"
  }

  assert {
    condition     = aws_db_instance.postgres.tags["Environment"] == "integration-test"
    error_message = "RDS must have Environment from common_tags"
  }

  assert {
    condition     = aws_db_instance.postgres.tags["ManagedBy"] == "terraform-test"
    error_message = "RDS must have ManagedBy from common_tags"
  }
}

#--------------------------------------------------------------
# 7. Output Contract — RDS ARN
#    Validates output structure for downstream consumption
#--------------------------------------------------------------

run "output_contract_valid" {
  command = apply

  variables {
    vpc_id                 = run.setup_infrastructure.vpc_id
    data_subnet_ids        = run.setup_infrastructure.data_subnet_ids
    data_security_group_id = run.setup_infrastructure.data_security_group_id
    instance_class         = "db.t3.micro"
    multi_az               = false
    backup_retention_period = 0
    deletion_protection     = false
    skip_final_snapshot     = true
    enhanced_monitoring_interval = 0
    enable_cloudwatch_alarms     = true
  }

  # RDS ARN must be valid
  assert {
    condition     = can(regex("^arn:aws:rds:", output.rds_arn))
    error_message = "RDS ARN must be valid RDS ARN"
  }

  # Address must not contain port
  assert {
    condition     = !can(regex(":", output.rds_address))
    error_message = "RDS address must not contain port (use rds_endpoint for host:port)"
  }

  # Endpoint must contain port
  assert {
    condition     = can(regex(":5432$", output.rds_endpoint))
    error_message = "RDS endpoint must end with :5432"
  }
}
