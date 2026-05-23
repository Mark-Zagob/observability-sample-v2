#--------------------------------------------------------------
# Security Module — Contract Tests (Plan Only)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/contract.tftest.hcl
# These tests ONLY run terraform plan — NO AWS resources created.
# Cost: $0.00
# Duration: ~10-15 seconds
#
# Purpose:
#   Validate input variable constraints, output shapes, and
#   configuration logic WITHOUT touching AWS. Use as CI gate
#   before expensive integration tests.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Test Setup: Create a real VPC for SG creation
#--------------------------------------------------------------
# Security module needs a real vpc_id (validated by regex).
# We use a mock override for plan-only tests.
#--------------------------------------------------------------

variables {
  project_name   = "inttest-sec"
  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.98.0.0/16"
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# 1. Variable Validation — project_name
#--------------------------------------------------------------

run "reject_uppercase_project_name" {
  command = plan

  variables {
    project_name = "BadName"
  }

  expect_failures = [var.project_name]
}

run "reject_spaces_in_project_name" {
  command = plan

  variables {
    project_name = "bad name"
  }

  expect_failures = [var.project_name]
}

#--------------------------------------------------------------
# 2. Variable Validation — vpc_id
#--------------------------------------------------------------

run "reject_invalid_vpc_id" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "reject_empty_vpc_id" {
  command = plan

  variables {
    vpc_id = ""
  }

  expect_failures = [var.vpc_id]
}

#--------------------------------------------------------------
# 3. Variable Validation — app_port
#--------------------------------------------------------------

run "reject_zero_app_port" {
  command = plan

  variables {
    app_port = 0
  }

  expect_failures = [var.app_port]
}

run "reject_port_above_65535" {
  command = plan

  variables {
    app_port = 70000
  }

  expect_failures = [var.app_port]
}

#--------------------------------------------------------------
# 4. Variable Validation — allowed_ssh_cidrs
#--------------------------------------------------------------

run "reject_invalid_ssh_cidr" {
  command = plan

  variables {
    allowed_ssh_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.allowed_ssh_cidrs]
}

#--------------------------------------------------------------
# 5. Variable Validation — vpc_cidr_block
#--------------------------------------------------------------

run "reject_invalid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr_block = "invalid"
  }

  expect_failures = [var.vpc_cidr_block]
}

#--------------------------------------------------------------
# 6. Default Values — Verify sensible defaults
#--------------------------------------------------------------

run "default_values_are_sensible" {
  command = plan

  assert {
    condition     = var.app_port == 8080
    error_message = "Default app_port must be 8080"
  }

  assert {
    condition     = var.enable_bastion == true
    error_message = "Default enable_bastion must be true"
  }

  assert {
    condition     = var.generate_ssh_key == true
    error_message = "Default generate_ssh_key must be true"
  }

  assert {
    condition     = var.app_health_check_port == 0
    error_message = "Default app_health_check_port must be 0 (same as app_port)"
  }

  assert {
    condition     = length(var.db_ports) == 4
    error_message = "Default db_ports must have 4 entries (postgres, mysql, redis, kafka)"
  }

  assert {
    condition     = length(var.monitoring_ports) == 5
    error_message = "Default monitoring_ports must have 5 entries"
  }
}
