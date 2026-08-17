#--------------------------------------------------------------
# VPC Endpoints Module — Integration Tests (Apply + Destroy)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/integration.tftest.hcl
# These tests APPLY real AWS resources and then DESTROY them.
# Cost: ~$0.00-$0.05 per run
#   - Gateway endpoints: FREE
#   - Interface endpoints: ~$0.01/hr per endpoint per AZ
#     (tests run <5 min → negligible cost)
# Duration: ~3-5 minutes
#
# Prerequisites:
#   - Valid AWS credentials
#   - Permissions: VPC, Subnets, Route Tables, VPC Endpoints,
#     Security Groups, EC2
#
# IMPORTANT — Test Ordering Strategy:
#   All run blocks share state. Tests scale UP only:
#     - Tests 1-4: Gateway endpoints only (FREE, no interface)
#     - Tests 5-7: Interface endpoints ON (scale up)
#   Final teardown destroys all resources.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Setup: Create test VPC + subnet + route table
#--------------------------------------------------------------

run "setup_vpc" {
  command = apply

  module {
    source = "./tests/setup"
  }

  variables {
    project_name = "inttest-vpce"
  }
}

#--------------------------------------------------------------
# Shared test variables
#--------------------------------------------------------------

variables {
  project_name = "inttest-vpce"
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# 1. S3 Gateway Endpoint — Smoke Test
#    Cloud architect: S3 endpoint must always exist.
#    Cost optimization: traffic avoids NAT → saves money.
#--------------------------------------------------------------

run "s3_gateway_endpoint_created" {
  command = apply

  variables {
    vpc_id                     = run.setup_vpc.vpc_id
    vpc_cidr                   = run.setup_vpc.vpc_cidr
    route_table_ids            = run.setup_vpc.route_table_ids
    private_subnet_ids         = run.setup_vpc.subnet_ids
    enable_s3_endpoint         = true
    enable_dynamodb_endpoint   = true
    enable_interface_endpoints = false
  }

  assert {
    condition     = startswith(output.s3_endpoint_id, "vpce-")
    error_message = "S3 Gateway Endpoint must have valid ID (vpce-xxx)"
  }

  assert {
    condition     = output.s3_endpoint_prefix_list_id != ""
    error_message = "S3 Endpoint must have a prefix list ID (for SG rules)"
  }
}

#--------------------------------------------------------------
# 2. DynamoDB Gateway Endpoint
#    Terraform state locking uses DynamoDB.
#--------------------------------------------------------------

run "dynamodb_gateway_endpoint_created" {
  command = apply

  variables {
    vpc_id                     = run.setup_vpc.vpc_id
    vpc_cidr                   = run.setup_vpc.vpc_cidr
    route_table_ids            = run.setup_vpc.route_table_ids
    private_subnet_ids         = run.setup_vpc.subnet_ids
    enable_s3_endpoint         = true
    enable_dynamodb_endpoint   = true
    enable_interface_endpoints = false
  }

  assert {
    condition     = startswith(output.dynamodb_endpoint_id, "vpce-")
    error_message = "DynamoDB Gateway Endpoint must have valid ID"
  }

  assert {
    condition     = output.dynamodb_endpoint_prefix_list_id != ""
    error_message = "DynamoDB Endpoint must have a prefix list ID"
  }
}

#--------------------------------------------------------------
# 3. Gateway Endpoints Map — Audit Output
#    Security auditor: verify all expected endpoints exist.
#--------------------------------------------------------------

run "gateway_endpoints_map_correct" {
  command = apply

  variables {
    vpc_id                     = run.setup_vpc.vpc_id
    vpc_cidr                   = run.setup_vpc.vpc_cidr
    route_table_ids            = run.setup_vpc.route_table_ids
    private_subnet_ids         = run.setup_vpc.subnet_ids
    enable_s3_endpoint         = true
    enable_dynamodb_endpoint   = true
    enable_interface_endpoints = false
  }

  assert {
    condition     = length(output.gateway_endpoints) == 2
    error_message = "Gateway endpoints map must have 2 entries (s3, dynamodb)"
  }

  assert {
    condition     = contains(keys(output.gateway_endpoints), "s3")
    error_message = "Gateway endpoints map must contain 's3' key"
  }

  assert {
    condition     = contains(keys(output.gateway_endpoints), "dynamodb")
    error_message = "Gateway endpoints map must contain 'dynamodb' key"
  }

  # No interface endpoints → no SG
  assert {
    condition     = output.endpoints_security_group_id == ""
    error_message = "SG must not be created when Interface Endpoints disabled"
  }
}

#--------------------------------------------------------------
# 4. S3 Endpoint Disabled — Verify Toggle Works
#--------------------------------------------------------------

run "s3_disabled_output_empty" {
  command = apply

  variables {
    vpc_id                     = run.setup_vpc.vpc_id
    vpc_cidr                   = run.setup_vpc.vpc_cidr
    route_table_ids            = run.setup_vpc.route_table_ids
    private_subnet_ids         = run.setup_vpc.subnet_ids
    enable_s3_endpoint         = false
    enable_dynamodb_endpoint   = true
    enable_interface_endpoints = false
  }

  assert {
    condition     = output.s3_endpoint_id == ""
    error_message = "S3 endpoint ID must be empty when disabled"
  }

  assert {
    condition     = length(output.gateway_endpoints) == 1
    error_message = "Only DynamoDB should remain in gateway map"
  }
}

#--------------------------------------------------------------
# 5. Interface Endpoints — Enable (Scale UP)
#    Senior devops: verify SG + endpoints created.
#    NOTE: This is the first test that enables interface endpoints.
#    Only scale UP from here — no scale-down mid-test.
#--------------------------------------------------------------

run "interface_endpoints_created" {
  command = apply

  variables {
    vpc_id                      = run.setup_vpc.vpc_id
    vpc_cidr                    = run.setup_vpc.vpc_cidr
    route_table_ids             = run.setup_vpc.route_table_ids
    private_subnet_ids          = run.setup_vpc.subnet_ids
    enable_s3_endpoint          = true
    enable_dynamodb_endpoint    = true
    enable_interface_endpoints  = true
    interface_endpoint_services = ["ssm", "sts"]  # Minimal set for faster tests
  }

  assert {
    condition     = startswith(output.endpoints_security_group_id, "sg-")
    error_message = "VPC Endpoints SG must have valid ID when interface endpoints enabled"
  }

  assert {
    condition     = length(output.interface_endpoint_ids) == 2
    error_message = "Must create exactly 2 interface endpoints (ssm, sts)"
  }

  assert {
    condition     = contains(keys(output.interface_endpoint_ids), "ssm")
    error_message = "Interface endpoint map must contain 'ssm'"
  }

  assert {
    condition     = contains(keys(output.interface_endpoint_ids), "sts")
    error_message = "Interface endpoint map must contain 'sts'"
  }
}

#--------------------------------------------------------------
# 6. Tags Applied — Verify on Real Resources
#--------------------------------------------------------------

run "tags_applied_to_endpoints" {
  command = apply

  variables {
    vpc_id                      = run.setup_vpc.vpc_id
    vpc_cidr                    = run.setup_vpc.vpc_cidr
    route_table_ids             = run.setup_vpc.route_table_ids
    private_subnet_ids          = run.setup_vpc.subnet_ids
    enable_s3_endpoint          = true
    enable_dynamodb_endpoint    = true
    enable_interface_endpoints  = true
    interface_endpoint_services = ["ssm", "sts"]
  }

  # S3 endpoint tags
  assert {
    condition     = aws_vpc_endpoint.s3[0].tags["Type"] == "gateway"
    error_message = "S3 endpoint must have Type=gateway tag"
  }

  # Interface endpoint tags
  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].tags["Type"] == "interface"
    error_message = "SSM endpoint must have Type=interface tag"
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].tags["Service"] == "ssm"
    error_message = "SSM endpoint must have Service=ssm tag"
  }

  # SG tags
  assert {
    condition     = aws_security_group.vpc_endpoints[0].tags["Tier"] == "infrastructure"
    error_message = "VPC Endpoints SG must have Tier=infrastructure tag"
  }

  # common_tags propagated
  assert {
    condition     = aws_vpc_endpoint.s3[0].tags["Environment"] == "integration-test"
    error_message = "S3 endpoint must have Environment from common_tags"
  }
}

#--------------------------------------------------------------
# 7. All Endpoint IDs — Audit List
#    Security auditor: flat list for compliance reporting.
#    This is the last test — teardown destroys everything.
#--------------------------------------------------------------

run "all_endpoint_ids_complete" {
  command = apply

  variables {
    vpc_id                      = run.setup_vpc.vpc_id
    vpc_cidr                    = run.setup_vpc.vpc_cidr
    route_table_ids             = run.setup_vpc.route_table_ids
    private_subnet_ids          = run.setup_vpc.subnet_ids
    enable_s3_endpoint          = true
    enable_dynamodb_endpoint    = true
    enable_interface_endpoints  = true
    interface_endpoint_services = ["ssm", "sts"]
  }

  # 2 gateway + 2 interface = 4 total
  assert {
    condition     = length(output.all_endpoint_ids) == 4
    error_message = "all_endpoint_ids must contain 4 entries (2 gateway + 2 interface)"
  }

  # All must be valid endpoint IDs
  assert {
    condition = alltrue([
      for id in output.all_endpoint_ids : startswith(id, "vpce-")
    ])
    error_message = "All endpoint IDs must be valid (vpce-xxx)"
  }
}
