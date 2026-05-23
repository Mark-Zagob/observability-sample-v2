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
  # Compact CIDR Allocation — Production Layout
  #------------------------------------------------------------
  #
  # Strategy:
  #   Level 1: VPC /16 → 2 halves /17
  #     - half_private: /17 → 8 × /20 blocks (private EKS/ECS workloads)
  #     - half_others:  /17 → 8 × /20 blocks (public, data, mgmt)
  #
  #   Level 2: Compact allocation inside half_others
  #     - Block[0]: Public subnets   (3 × /24, 762 usable IPs)
  #     - Block[1]: SHARED small tiers (Data + Mgmt packed together)
  #       ├── Data subnets   (3 × /26, 186 usable IPs)
  #       └── Mgmt subnets   (3 × /27, 90 usable IPs)
  #     - Block[2-7]: 6 × /20 FULLY reserved for future expansion
  #
  # Benefits vs old layout:
  #   - Saves 2 whole /20 blocks (8,192 IPs) that were wasted on
  #     near-empty Data/Mgmt blocks
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


  # Level 4: Mgmt subnets — /27 from block[1] (offset after Data CIDRs)
  # Data uses indices 0-2 of /26 (each /26 = 2 × /27), so Mgmt starts at /27 index 6+
  # But to avoid overlap we carve Mgmt from the second half of block[1]:
  #   block[1] = /20 → split into 2 × /21
  #   Data from first /21, Mgmt from second /21
  shared_block_data = cidrsubnet(local.others_blocks[1], 1, 0)
  shared_block_mgmt = cidrsubnet(local.others_blocks[1], 1, 1)

  data_cidrs = { for k, az in local.az_map : k => cidrsubnet(local.shared_block_data, 5, index(keys(local.az_map), k)) }
  mgmt_cidrs = { for k, az in local.az_map : k => cidrsubnet(local.shared_block_mgmt, 6, index(keys(local.az_map), k)) }
}
