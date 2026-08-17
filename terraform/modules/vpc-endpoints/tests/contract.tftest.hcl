#--------------------------------------------------------------
# VPC Endpoints Module — Contract Tests (Plan Only)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/contract.tftest.hcl
# Cost: $0.00 — no AWS resources created
# Duration: ~10 seconds
#--------------------------------------------------------------

variables {
  project_name = "inttest-vpce"
  vpc_id       = "vpc-0123456789abcdef0"
  vpc_cidr     = "10.98.0.0/16"
  route_table_ids    = ["rtb-0123456789abcdef0"]
  private_subnet_ids = ["subnet-0123456789abcdef0"]
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
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

#--------------------------------------------------------------
# 3. Variable Validation — vpc_cidr
#--------------------------------------------------------------

run "reject_invalid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "invalid"
  }

  expect_failures = [var.vpc_cidr]
}

#--------------------------------------------------------------
# 4. Variable Validation — route_table_ids
#--------------------------------------------------------------

run "reject_empty_route_table_ids" {
  command = plan

  variables {
    route_table_ids = []
  }

  expect_failures = [var.route_table_ids]
}

#--------------------------------------------------------------
# 5. Default Values — Gateway endpoints ON, Interface OFF
#--------------------------------------------------------------

run "defaults_are_sensible" {
  command = plan

  assert {
    condition     = var.enable_s3_endpoint == true
    error_message = "S3 Gateway Endpoint should be enabled by default (FREE)"
  }

  assert {
    condition     = var.enable_dynamodb_endpoint == true
    error_message = "DynamoDB Gateway Endpoint should be enabled by default (FREE)"
  }

  assert {
    condition     = var.enable_interface_endpoints == false
    error_message = "Interface Endpoints should be disabled by default (costs money)"
  }

  assert {
    condition     = length(var.interface_endpoint_services) == 7
    error_message = "Default interface services must have 7 entries"
  }
}

#--------------------------------------------------------------
# 6. Gateway endpoints toggleable
#--------------------------------------------------------------

run "s3_endpoint_disabled_produces_empty_output" {
  command = plan

  variables {
    enable_s3_endpoint = false
  }

  assert {
    condition     = output.s3_endpoint_id == ""
    error_message = "S3 endpoint ID must be empty string when disabled"
  }
}

run "dynamodb_endpoint_disabled_produces_empty_output" {
  command = plan

  variables {
    enable_dynamodb_endpoint = false
  }

  assert {
    condition     = output.dynamodb_endpoint_id == ""
    error_message = "DynamoDB endpoint ID must be empty string when disabled"
  }
}

#--------------------------------------------------------------
# 7. Interface disabled — SG not created
#--------------------------------------------------------------

run "interface_disabled_sg_empty" {
  command = plan

  variables {
    enable_interface_endpoints = false
  }

  assert {
    condition     = output.endpoints_security_group_id == ""
    error_message = "SG ID must be empty string when Interface Endpoints disabled"
  }

  assert {
    condition     = length(output.interface_endpoint_ids) == 0
    error_message = "Interface endpoint map must be empty when disabled"
  }
}
