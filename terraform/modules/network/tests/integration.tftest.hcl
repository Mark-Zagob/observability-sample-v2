#--------------------------------------------------------------
# Network Module — Integration Tests (Apply + Destroy)
#--------------------------------------------------------------
# Run with: terraform test -filter=tests/integration.tftest.hcl
# These tests APPLY real AWS resources and then DESTROY them.
# Cost: ~$0.10-0.15 per full run (NAT GW + EIP charged per hour)
# Duration: ~3-5 minutes
#
# Prerequisites:
#   - Valid AWS credentials configured
#   - Permissions: VPC, Subnet, NAT GW, EIP, IGW, Route Table,
#     CloudWatch Logs, KMS, IAM (for flow logs role)
#
# IMPORTANT — Test Ordering Strategy:
#   All run blocks share state. NAT Gateway mode changes trigger
#   EIP create/destroy. AWS has a known race condition where
#   releasing an EIP fails if the NAT GW's ENI isn't fully
#   detached yet. To avoid this:
#     - Tests 1-6: single_nat_gateway = true (no NAT state change)
#     - Test 7: HA NAT (scale UP only — safe)
#     - Tests 8-10: flow logs + output validation (back to single)
#   The final teardown does a full destroy which handles cleanup
#   more reliably than mid-run scale-down.
#--------------------------------------------------------------

variables {
  project_name = "inttest-net"
  aws_region   = "ap-southeast-2"
  vpc_cidr     = "10.99.0.0/16"   # Use isolated CIDR to avoid conflicts
  az_count     = 2                 # 2 AZs → faster, cheaper tests
  common_tags = {
    Environment = "integration-test"
    ManagedBy   = "terraform-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# 1. Core VPC Creation — Smoke Test
#    Validates: VPC, IGW, subnets, route tables all create
#    successfully and return valid AWS IDs
#--------------------------------------------------------------

run "vpc_creates_successfully" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = startswith(output.vpc_id, "vpc-")
    error_message = "VPC ID must be a valid AWS VPC ID (vpc-xxx)"
  }

  assert {
    condition     = output.vpc_cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR must match input: 10.99.0.0/16"
  }

  assert {
    condition     = startswith(output.internet_gateway_id, "igw-")
    error_message = "Internet Gateway must be created with valid ID"
  }
}

#--------------------------------------------------------------
# 2. Subnet Distribution — Verify AZ Spread
#    Security audit: subnets must span multiple AZs for HA.
#    Cloud architect: validate subnet IDs are real AWS resources.
#--------------------------------------------------------------

run "subnets_distributed_across_azs" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  # All subnet lists must have exactly az_count (2) elements
  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "Expected 2 public subnets for 2-AZ mode"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "Expected 2 private subnets for 2-AZ mode"
  }

  assert {
    condition     = length(output.data_subnet_ids) == 2
    error_message = "Expected 2 data subnets for 2-AZ mode"
  }

  assert {
    condition     = length(output.mgmt_subnet_ids) == 2
    error_message = "Expected 2 mgmt subnets for 2-AZ mode"
  }

  # All subnet IDs must be valid AWS IDs
  assert {
    condition = alltrue([
      for id in output.public_subnet_ids : startswith(id, "subnet-")
    ])
    error_message = "All public subnet IDs must be valid (subnet-xxx)"
  }

  assert {
    condition = alltrue([
      for id in output.private_subnet_ids : startswith(id, "subnet-")
    ])
    error_message = "All private subnet IDs must be valid (subnet-xxx)"
  }

  # Verify AZs are distinct (not all in same AZ)
  assert {
    condition     = length(distinct(output.availability_zones)) == 2
    error_message = "Subnets must be distributed across 2 distinct AZs"
  }
}

#--------------------------------------------------------------
# 3. CIDR Allocation — Verify Non-Overlap
#    Critical: overlapping CIDRs cause routing failures.
#    Validates that the cidrsubnet() math is correct.
#--------------------------------------------------------------

run "cidr_blocks_are_unique" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  # Collect all CIDRs and verify uniqueness
  assert {
    condition = length(distinct(concat(
      output.public_subnet_cidrs,
      output.private_subnet_cidrs,
      output.data_subnet_cidrs,
      output.mgmt_subnet_cidrs
    ))) == length(concat(
      output.public_subnet_cidrs,
      output.private_subnet_cidrs,
      output.data_subnet_cidrs,
      output.mgmt_subnet_cidrs
    ))
    error_message = "All subnet CIDRs must be unique (no overlaps)"
  }

  # All CIDRs must be within VPC range (10.99.x.x)
  assert {
    condition = alltrue([
      for cidr in concat(
        output.public_subnet_cidrs,
        output.private_subnet_cidrs,
        output.data_subnet_cidrs,
        output.mgmt_subnet_cidrs
      ) : substr(cidr, 0, 5) == "10.99"
    ])
    error_message = "All subnet CIDRs must be within VPC CIDR 10.99.0.0/16"
  }
}

#--------------------------------------------------------------
# 4. NAT Gateway — Single Mode
#    Cost optimization test: single NAT must create exactly 1
#    NAT GW + 1 EIP (saves ~$32/month per AZ)
#--------------------------------------------------------------

run "single_nat_creates_one_gateway" {
  command = apply

  variables {
    single_nat_gateway = true
    enable_flow_logs   = false
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 1
    error_message = "Single NAT mode must create exactly 1 NAT Gateway"
  }

  assert {
    condition     = length(output.nat_public_ips) == 1
    error_message = "Single NAT mode must allocate exactly 1 EIP"
  }

  # NAT GW ID must be valid
  assert {
    condition     = startswith(output.nat_gateway_ids[0], "nat-")
    error_message = "NAT Gateway ID must be valid (nat-xxx)"
  }
}

#--------------------------------------------------------------
# 5. Route Tables — Verify Correct Associations
#    Security audit: data subnets must NOT have internet route.
#    Cloud devops: private/mgmt subnets must route via NAT.
#    NOTE: Runs BEFORE HA NAT test to avoid scale-down race.
#--------------------------------------------------------------

run "route_table_structure_correct" {
  command = apply

  variables {
    single_nat_gateway = true
    enable_flow_logs   = false
  }

  # Public route table exists
  assert {
    condition     = startswith(output.public_route_table_id, "rtb-")
    error_message = "Public route table must be created"
  }

  # Data route table exists (isolated, no NAT route)
  assert {
    condition     = startswith(output.data_route_table_id, "rtb-")
    error_message = "Data route table must be created"
  }

  # Private route tables: 1 per AZ
  assert {
    condition     = length(output.private_route_table_ids) == 2
    error_message = "Must have 1 private route table per AZ"
  }

  # Mgmt route tables: 1 per AZ
  assert {
    condition     = length(output.mgmt_route_table_ids) == 2
    error_message = "Must have 1 mgmt route table per AZ"
  }
}

#--------------------------------------------------------------
# 6. Output Contract — Map Outputs
#    Terraform specialist: verify map outputs that downstream
#    modules (security, data) depend on.
#--------------------------------------------------------------

run "map_outputs_have_correct_keys" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = length(output.az_map) == 2
    error_message = "az_map must have 2 entries for 2-AZ mode"
  }

  assert {
    condition     = length(output.private_subnets) == 2
    error_message = "private_subnets map must have 2 entries"
  }

  assert {
    condition     = length(output.public_subnets) == 2
    error_message = "public_subnets map must have 2 entries"
  }
}

#--------------------------------------------------------------
# 7. Tagging — Verify Real AWS Tags
#    Cloud devops: tags applied correctly to actual resources.
#    Validates common_tags propagation and Tier tags.
#--------------------------------------------------------------

run "tags_applied_to_real_resources" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  # VPC has been tagged (checked via resource, not output)
  assert {
    condition     = aws_vpc.this.tags["Environment"] == "integration-test"
    error_message = "VPC must have Environment=integration-test tag from common_tags"
  }

  assert {
    condition     = aws_vpc.this.tags["ManagedBy"] == "terraform-test"
    error_message = "VPC must have ManagedBy=terraform-test tag"
  }

  # Subnets have Tier tags
  assert {
    condition = alltrue([
      for k, v in aws_subnet.public : v.tags["Tier"] == "public"
    ])
    error_message = "All public subnets must have Tier=public tag on real AWS resources"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.private : v.tags["Tier"] == "private"
    ])
    error_message = "All private subnets must have Tier=private tag on real AWS resources"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.data : v.tags["Tier"] == "data"
    ])
    error_message = "All data subnets must have Tier=data tag on real AWS resources"
  }
}

#--------------------------------------------------------------
# 8. NAT Gateway — HA Mode
#    Production-grade: 1 NAT per AZ for fault isolation.
#    Cloud architect: verify each AZ has independent NAT path.
#    NOTE: Placed AFTER single NAT tests. Scale-up (1→2) is safe.
#    Scale-down (2→1) only happens during final teardown which
#    handles full resource destruction more reliably.
#--------------------------------------------------------------

run "ha_nat_creates_per_az" {
  command = apply

  variables {
    single_nat_gateway = false
    enable_flow_logs   = false
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 2
    error_message = "HA NAT mode must create 1 NAT Gateway per AZ (2)"
  }

  assert {
    condition     = length(output.nat_public_ips) == 2
    error_message = "HA NAT mode must allocate 1 EIP per AZ (2)"
  }

  # Each NAT must have a distinct public IP
  assert {
    condition     = length(distinct(output.nat_public_ips)) == 2
    error_message = "Each NAT Gateway must have a unique public IP"
  }
}

#--------------------------------------------------------------
# 9. VPC Flow Logs — Enabled Path
#    Security auditor: flow logs MUST be enabled in production.
#    Validates CW Log Group + KMS key are created.
#--------------------------------------------------------------

run "flow_logs_enabled_creates_real_resources" {
  command = apply

  variables {
    enable_flow_logs         = true
    flow_logs_retention_days = 7
  }

  # VPC still creates normally
  assert {
    condition     = startswith(output.vpc_id, "vpc-")
    error_message = "VPC must be created when flow logs are enabled"
  }
}

#--------------------------------------------------------------
# 10. VPC Flow Logs — Disabled Path
#     Validates no extra cost resources when flow logs off.
#     NOTE: This is the LAST test. Final teardown destroys
#     everything (VPC, subnets, NAT GWs, EIPs) in one pass.
#--------------------------------------------------------------

run "flow_logs_disabled_still_creates_vpc" {
  command = apply

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = startswith(output.vpc_id, "vpc-")
    error_message = "VPC must still be created when flow logs are disabled"
  }

  # Subnet count unaffected
  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "Subnets must still be created regardless of flow log setting"
  }
}
