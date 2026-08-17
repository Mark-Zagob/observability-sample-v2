#--------------------------------------------------------------
# Data Sources & Locals
#--------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Map of AZ short name → full AZ name (for for_each keys)
  # Example: { "a" = "ap-southeast-1a", "b" = "ap-southeast-1b", "c" = "ap-southeast-1c" }
  az_map = { for az in local.azs : substr(az, -1, 1) => az }

  # NAT Gateway: 1 per AZ (HA) or single (cost-saving)
  nat_az_map = var.single_nat_gateway ? { (keys(local.az_map)[0]) = values(local.az_map)[0] } : local.az_map

  #------------------------------------------------------------
  # Compact CIDR Allocation — 3-Tier Layout (Post-Refactor)
  #------------------------------------------------------------
  #
  # Strategy:
  #   Level 1: VPC /16 → 2 halves /17
  #     - half_private: /17 → 8 × /20 blocks (private EKS/ECS workloads)
  #     - half_others:  /17 → 8 × /20 blocks (public, data)
  #
  #   Level 2: Compact allocation inside half_others
  #     - Block[0]: Public subnets   (3 × /24, 768 usable IPs)
  #     - Block[1]: Data subnets     (3 × /24, 768 usable IPs) ✅ Increased from /26
  #     - Block[2-7]: 6 × /20 FULLY reserved for future expansion
  #
  # Benefits vs old 4-tier layout:
  #   - Data tier now has 256 IPs/AZ (vs 64 IPs with /26)
  #   - Saves 3 subnets, 3 route tables, 3 NACLs
  #   - Bastion host moved to Private tier (SSM Session Manager)
  #   - All CIDRs derived from var.vpc_cidr — zero hardcoded IPs
  #------------------------------------------------------------

  # Level 1: split VPC into 2 halves
  half_private = cidrsubnet(var.vpc_cidr, 1, 0) # 10.0.0.0/17
  half_others  = cidrsubnet(var.vpc_cidr, 1, 1) # 10.0.128.0/17

  # Level 2: Private subnets — /20 per AZ (4,096 IPs for EKS pods)
  private_cidrs = { for k, az in local.az_map : k => cidrsubnet(local.half_private, 3, index(keys(local.az_map), k)) }

  # Level 3: Others blocks — split half_others into 8 × /20
  others_blocks = [for i in range(8) : cidrsubnet(local.half_others, 3, i)]

  # Level 4: Public subnets — /24 from block[0]
  public_cidrs = { for k, az in local.az_map : k => cidrsubnet(local.others_blocks[0], 4, index(keys(local.az_map), k)) }

  # Level 4: Data subnets — /24 from block[1] (increased from /26)
  data_cidrs = { for k, az in local.az_map : k => cidrsubnet(local.others_blocks[1], 4, index(keys(local.az_map), k)) }
}