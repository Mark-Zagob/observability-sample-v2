#--------------------------------------------------------------
# Network Module — Contract Tests (Plan-Only)
#--------------------------------------------------------------
# Run with: terraform test
# These tests only run `plan` — NO real resources created.
#--------------------------------------------------------------

variables {
  project_name = "test-network"
  aws_region   = "ap-southeast-1"
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 3
  common_tags = {
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

#--------------------------------------------------------------
# 1. Subnet Count Tests
#--------------------------------------------------------------

run "subnet_count_matches_az_count" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == var.az_count
    error_message = "Private subnet count (${length(aws_subnet.private)}) must equal az_count (${var.az_count})"
  }

  assert {
    condition     = length(aws_subnet.public) == var.az_count
    error_message = "Public subnet count must equal az_count"
  }

  assert {
    condition     = length(aws_subnet.data) == var.az_count
    error_message = "Data subnet count must equal az_count"
  }

  assert {
    condition     = length(aws_subnet.mgmt) == var.az_count
    error_message = "Mgmt subnet count must equal az_count"
  }
}

#--------------------------------------------------------------
# 2. VPC Configuration Tests
#--------------------------------------------------------------

run "vpc_configuration_correct" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR must match input variable"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support must be enabled"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames must be enabled (required for VPC Endpoints)"
  }
}

#--------------------------------------------------------------
# 3. CIDR Non-Overlap Tests
#    Most critical — validates the compact CIDR allocation logic
#--------------------------------------------------------------

run "private_cidrs_are_slash_20" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.private :
      endswith(v.cidr_block, "/20")
    ])
    error_message = "All private subnets must be /20 for EKS pod density"
  }
}

run "public_cidrs_are_slash_24" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.public :
      endswith(v.cidr_block, "/24")
    ])
    error_message = "All public subnets must be /24"
  }
}

run "data_cidrs_are_slash_26" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.data :
      endswith(v.cidr_block, "/26")
    ])
    error_message = "All data subnets must be /26"
  }
}

run "mgmt_cidrs_are_slash_27" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.mgmt :
      endswith(v.cidr_block, "/27")
    ])
    error_message = "All mgmt subnets must be /27"
  }
}

run "all_subnets_within_vpc_cidr" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.private :
      cidrcontains("10.0.0.0/16", v.cidr_block)
    ])
    error_message = "All private subnets must be within VPC CIDR"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.public :
      cidrcontains("10.0.0.0/16", v.cidr_block)
    ])
    error_message = "All public subnets must be within VPC CIDR"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.data :
      cidrcontains("10.0.0.0/16", v.cidr_block)
    ])
    error_message = "All data subnets must be within VPC CIDR"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.mgmt :
      cidrcontains("10.0.0.0/16", v.cidr_block)
    ])
    error_message = "All mgmt subnets must be within VPC CIDR"
  }
}

#--------------------------------------------------------------
# 4. NAT Gateway Tests — Single vs HA
#--------------------------------------------------------------

run "single_nat_gateway_creates_one" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Single NAT mode must create exactly 1 NAT Gateway"
  }
}

run "ha_nat_gateway_creates_per_az" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == var.az_count
    error_message = "HA NAT mode must create 1 NAT Gateway per AZ"
  }
}

#--------------------------------------------------------------
# 5. Flow Logs Conditional Tests
#--------------------------------------------------------------

run "flow_logs_enabled_creates_resources" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition     = length(aws_flow_log.this) == 1
    error_message = "Enabling flow logs must create exactly 1 flow log"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_logs) == 1
    error_message = "Enabling flow logs must create a CloudWatch Log Group"
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 1
    error_message = "Enabling flow logs must create a KMS key for encryption"
  }
}

run "flow_logs_disabled_creates_nothing" {
  command = plan

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = length(aws_flow_log.this) == 0
    error_message = "Disabling flow logs must not create any flow log resources"
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 0
    error_message = "Disabling flow logs must not create KMS key"
  }
}

#--------------------------------------------------------------
# 6. Security — Flow Logs Encryption
#--------------------------------------------------------------

run "flow_logs_log_group_encrypted" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition = alltrue([
      for k, v in aws_cloudwatch_log_group.flow_logs :
      v.kms_key_id != null && v.kms_key_id != ""
    ])
    error_message = "Flow Logs CloudWatch Log Group must be encrypted with KMS"
  }
}

run "kms_key_rotation_enabled" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition = alltrue([
      for k, v in aws_kms_key.flow_logs :
      v.enable_key_rotation == true
    ])
    error_message = "KMS key must have automatic rotation enabled (CIS Benchmark)"
  }
}

#--------------------------------------------------------------
# 7. Tagging Tests
#--------------------------------------------------------------

run "all_subnets_have_tier_tag" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in aws_subnet.public :
      lookup(v.tags, "Tier", "") == "public"
    ])
    error_message = "All public subnets must have Tier=public tag"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.private :
      lookup(v.tags, "Tier", "") == "private"
    ])
    error_message = "All private subnets must have Tier=private tag"
  }

  assert {
    condition = alltrue([
      for k, v in aws_subnet.data :
      lookup(v.tags, "Tier", "") == "data"
    ])
    error_message = "All data subnets must have Tier=data tag"
  }
}

#--------------------------------------------------------------
# 8. Output Contract Tests
#--------------------------------------------------------------

run "outputs_expose_correct_counts" {
  command = plan

  assert {
    condition     = length(output.public_subnet_ids) == var.az_count
    error_message = "Output public_subnet_ids must have az_count elements"
  }

  assert {
    condition     = length(output.private_subnet_ids) == var.az_count
    error_message = "Output private_subnet_ids must have az_count elements"
  }

  assert {
    condition     = length(output.data_subnet_ids) == var.az_count
    error_message = "Output data_subnet_ids must have az_count elements"
  }
}

#--------------------------------------------------------------
# 9. Two AZ Mode Tests
#--------------------------------------------------------------

run "two_az_mode_works" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "2-AZ mode must create exactly 2 private subnets"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "2-AZ mode must create exactly 2 public subnets"
  }
}
