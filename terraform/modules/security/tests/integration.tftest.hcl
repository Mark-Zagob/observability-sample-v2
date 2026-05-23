#--------------------------------------------------------------
# Security Module — Integration Tests (Apply + Destroy)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/integration.tftest.hcl
# These tests APPLY real AWS resources and then DESTROY them.
# Cost: ~$0.01-0.02 per run (SGs, IAM, Key Pair — mostly free)
# Duration: ~2-4 minutes
#
# Prerequisites:
#   - Valid AWS credentials configured
#   - Permissions: VPC, Security Groups, IAM Roles/Policies,
#     IAM Instance Profiles, EC2 Key Pairs, TLS
#
# IMPORTANT — Test Ordering Strategy:
#   All run blocks share state. To avoid state conflicts:
#     - Tests 1-7: enable_bastion = true (bastion ON)
#     - Test 8: enable_bastion = false (scale DOWN)
#     - Test 9: Back to bastion enabled (scale UP for teardown)
#   Bastion toggle is safe (no EIP/ENI race) unlike NAT GW.
#
# Resource Dependencies:
#   This module requires a real VPC ID (regex-validated input).
#   A helper setup module creates a minimal VPC for testing.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Setup: Create test VPC
#--------------------------------------------------------------

run "setup_vpc" {
  command = apply

  module {
    source = "./tests/setup"
  }

  variables {
    project_name = "inttest-sec"
  }
}

#--------------------------------------------------------------
# Shared test variables
#--------------------------------------------------------------

variables {
  project_name = "inttest-sec"
  app_port     = 8080
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# 1. Core Security Groups — Smoke Test
#    Validates: All 5 core SGs + bastion SG are created
#    and return valid AWS Security Group IDs
#--------------------------------------------------------------

run "core_security_groups_created" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  # All 5 core SGs must be valid AWS SG IDs
  assert {
    condition     = startswith(output.alb_security_group_id, "sg-")
    error_message = "ALB Security Group must have valid ID (sg-xxx)"
  }

  assert {
    condition     = startswith(output.application_security_group_id, "sg-")
    error_message = "Application Security Group must have valid ID"
  }

  assert {
    condition     = startswith(output.data_security_group_id, "sg-")
    error_message = "Data Security Group must have valid ID"
  }

  assert {
    condition     = startswith(output.efs_security_group_id, "sg-")
    error_message = "EFS Security Group must have valid ID"
  }

  assert {
    condition     = startswith(output.observability_security_group_id, "sg-")
    error_message = "Observability Security Group must have valid ID"
  }

  # Bastion SG must be created when enabled
  assert {
    condition     = startswith(output.bastion_security_group_id, "sg-")
    error_message = "Bastion Security Group must be created when enable_bastion=true"
  }
}

#--------------------------------------------------------------
# 2. SG Uniqueness — All SGs Must Be Distinct
#    Security audit: shared SG IDs between tiers would
#    break defense-in-depth isolation.
#--------------------------------------------------------------

run "all_security_groups_are_unique" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  assert {
    condition = length(distinct([
      output.alb_security_group_id,
      output.application_security_group_id,
      output.data_security_group_id,
      output.efs_security_group_id,
      output.observability_security_group_id,
      output.bastion_security_group_id,
    ])) == 6
    error_message = "All 6 security groups must have unique IDs (defense-in-depth)"
  }
}

#--------------------------------------------------------------
# 3. Security Group Map Output — for_each Compatibility
#    Terraform specialist: downstream modules use
#    security_group_ids map for bulk operations.
#--------------------------------------------------------------

run "sg_map_output_has_correct_keys" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  assert {
    condition     = length(output.security_group_ids) == 6
    error_message = "security_group_ids map must have 6 entries"
  }

  # Verify all expected keys exist
  assert {
    condition     = contains(keys(output.security_group_ids), "alb")
    error_message = "security_group_ids must contain 'alb' key"
  }

  assert {
    condition     = contains(keys(output.security_group_ids), "application")
    error_message = "security_group_ids must contain 'application' key"
  }

  assert {
    condition     = contains(keys(output.security_group_ids), "data")
    error_message = "security_group_ids must contain 'data' key"
  }

  assert {
    condition     = contains(keys(output.security_group_ids), "efs")
    error_message = "security_group_ids must contain 'efs' key"
  }

  assert {
    condition     = contains(keys(output.security_group_ids), "observability")
    error_message = "security_group_ids must contain 'observability' key"
  }

  assert {
    condition     = contains(keys(output.security_group_ids), "bastion")
    error_message = "security_group_ids must contain 'bastion' key"
  }
}

#--------------------------------------------------------------
# 4. IAM Roles — ECS Task Execution & Task Roles
#    AWS Well-Architected: separate infra-level (execution)
#    and app-level (task) roles for least-privilege.
#--------------------------------------------------------------

run "ecs_iam_roles_created" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  # Task Execution Role (infra-level: ECR pull, CW logs)
  assert {
    condition     = can(regex("^arn:aws:iam::", output.ecs_task_execution_role_arn))
    error_message = "ECS Task Execution Role ARN must be valid IAM ARN"
  }

  assert {
    condition     = output.ecs_task_execution_role_name == "inttest-sec-ecs-task-execution"
    error_message = "ECS Task Execution Role name must follow naming convention"
  }

  # Task Role (app-level: S3, SQS, DynamoDB)
  assert {
    condition     = can(regex("^arn:aws:iam::", output.ecs_task_role_arn))
    error_message = "ECS Task Role ARN must be valid IAM ARN"
  }

  assert {
    condition     = output.ecs_task_role_name == "inttest-sec-ecs-task"
    error_message = "ECS Task Role name must follow naming convention"
  }

  # Roles must be distinct
  assert {
    condition     = output.ecs_task_execution_role_arn != output.ecs_task_role_arn
    error_message = "Task Execution and Task roles must be separate (least-privilege)"
  }
}

#--------------------------------------------------------------
# 5. Bastion IAM — Instance Profile + SSM Support
#    Senior security: bastion must have SSM for secure access.
#--------------------------------------------------------------

run "bastion_iam_created_when_enabled" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  assert {
    condition     = can(regex("^arn:aws:iam::", output.bastion_instance_profile_arn))
    error_message = "Bastion Instance Profile ARN must be valid when enabled"
  }

  assert {
    condition     = output.bastion_instance_profile_name == "inttest-sec-bastion"
    error_message = "Bastion Instance Profile name must follow naming convention"
  }

  assert {
    condition     = can(regex("^arn:aws:iam::", output.bastion_role_arn))
    error_message = "Bastion IAM Role ARN must be valid when enabled"
  }
}

#--------------------------------------------------------------
# 6. SSH Key Pair — Auto-Generate Mode (Lab)
#    Cloud devops: lab mode auto-creates key pair.
#--------------------------------------------------------------

run "ssh_key_generated_in_lab_mode" {
  command = apply

  variables {
    vpc_id           = run.setup_vpc.vpc_id
    vpc_cidr_block   = run.setup_vpc.vpc_cidr_block
    enable_bastion   = true
    generate_ssh_key = true
  }

  assert {
    condition     = output.key_pair_name == "inttest-sec-bastion"
    error_message = "Key pair name must follow project naming convention"
  }
}

#--------------------------------------------------------------
# 7. Tagging — Verify Tags on Real AWS Resources
#    Cloud architect: tags must propagate to actual resources.
#--------------------------------------------------------------

run "tags_applied_to_security_groups" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  # ALB SG has correct Tier tag
  assert {
    condition     = aws_security_group.alb.tags["Tier"] == "public"
    error_message = "ALB SG must have Tier=public tag"
  }

  # Application SG has correct Tier tag
  assert {
    condition     = aws_security_group.application.tags["Tier"] == "private"
    error_message = "Application SG must have Tier=private tag"
  }

  # Data SG has correct Tier tag
  assert {
    condition     = aws_security_group.data.tags["Tier"] == "data"
    error_message = "Data SG must have Tier=data tag"
  }

  # common_tags propagated
  assert {
    condition     = aws_security_group.alb.tags["Environment"] == "integration-test"
    error_message = "ALB SG must have Environment=integration-test from common_tags"
  }

  assert {
    condition     = aws_security_group.alb.tags["ManagedBy"] == "terraform-test"
    error_message = "ALB SG must have ManagedBy=terraform-test from common_tags"
  }

  # Bastion SG has correct Tier tag
  assert {
    condition     = aws_security_group.bastion[0].tags["Tier"] == "mgmt"
    error_message = "Bastion SG must have Tier=mgmt tag"
  }
}

#--------------------------------------------------------------
# 8. Bastion Disabled — Conditional Resources
#    Terraform specialist: verify count-based resources properly
#    toggle off without errors.
#    NOTE: Scale DOWN bastion (enabled → disabled)
#--------------------------------------------------------------

run "bastion_disabled_removes_resources" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = false
  }

  # Core SGs still created
  assert {
    condition     = startswith(output.alb_security_group_id, "sg-")
    error_message = "ALB SG must still exist when bastion is disabled"
  }

  assert {
    condition     = startswith(output.application_security_group_id, "sg-")
    error_message = "Application SG must still exist when bastion is disabled"
  }

  # Bastion outputs must be empty strings
  assert {
    condition     = output.bastion_security_group_id == ""
    error_message = "Bastion SG ID must be empty string when disabled"
  }

  assert {
    condition     = output.bastion_instance_profile_name == ""
    error_message = "Bastion Instance Profile must be empty string when disabled"
  }

  assert {
    condition     = output.bastion_instance_profile_arn == ""
    error_message = "Bastion Instance Profile ARN must be empty string when disabled"
  }

  assert {
    condition     = output.bastion_role_arn == ""
    error_message = "Bastion Role ARN must be empty string when disabled"
  }

  assert {
    condition     = output.key_pair_name == ""
    error_message = "Key pair name must be empty string when bastion disabled"
  }

  # ECS roles must still exist (independent of bastion)
  assert {
    condition     = can(regex("^arn:aws:iam::", output.ecs_task_execution_role_arn))
    error_message = "ECS Task Execution Role must exist regardless of bastion toggle"
  }

  # Map output should have bastion as empty string
  assert {
    condition     = output.security_group_ids["bastion"] == ""
    error_message = "security_group_ids map bastion entry must be empty when disabled"
  }
}

#--------------------------------------------------------------
# 9. Re-enable Bastion — Scale Up for Clean Teardown
#    Ensure bastion resources can be recreated after disable.
#    Final teardown handles full destroy.
#--------------------------------------------------------------

run "bastion_re_enabled_creates_resources" {
  command = apply

  variables {
    vpc_id         = run.setup_vpc.vpc_id
    vpc_cidr_block = run.setup_vpc.vpc_cidr_block
    enable_bastion = true
  }

  assert {
    condition     = startswith(output.bastion_security_group_id, "sg-")
    error_message = "Bastion SG must be recreated when re-enabled"
  }

  assert {
    condition     = output.bastion_instance_profile_name == "inttest-sec-bastion"
    error_message = "Bastion Instance Profile must be recreated when re-enabled"
  }

  assert {
    condition     = output.key_pair_name == "inttest-sec-bastion"
    error_message = "Key pair must be recreated when re-enabled"
  }
}
