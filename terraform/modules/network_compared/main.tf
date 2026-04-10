#--------------------------------------------------------------
# Network Module - VPC, Subnets, IGW, NAT Gateway
# VPC Endpoints, Flow Logs
#--------------------------------------------------------------

#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------
#
# [FIX #1] Lấy AZs dynamic thay vì hardcode a/b/c
# Lý do: không phải region nào cũng có 3 AZs giống nhau
# data source sẽ trả về danh sách AZs thực tế "available" trong region

locals {
  # NAT Gateway count: 1 (cost-saving) or 3 (HA per-AZ)
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.avai_zones)

  # Level 1
  half_private = cidrsubnet(var.vpc_cidr, 1, 0)
  half_others  = cidrsubnet(var.vpc_cidr, 1, 1)

  # Level 2: Private subnets
  private_cidrs = [for i in range(length(var.avai_zones)) : cidrsubnet(local.half_private, 3, i)]

  # Level 3: Chia half_others thành các block /20
  others_blocks = [for i in range(8) : cidrsubnet(local.half_others, 3, i)]

  public_cidrs = [for i in range(length(var.avai_zones)) : cidrsubnet(local.others_blocks[0], 4, i)] # /24
  data_cidrs   = [for i in range(length(var.avai_zones)) : cidrsubnet(local.others_blocks[1], 6, i)] # /26 #cursor recommennd /24 for large envs
  mgmt_cidrs   = [for i in range(length(var.avai_zones)) : cidrsubnet(local.others_blocks[2], 7, i)] # /27 #cursor recommennd /26 for large envs
}

#--------------------------------------------------------------
# VPC
#--------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-vpc"
  })
}

#--------------------------------------------------------------
# Internet Gateway
#--------------------------------------------------------------
# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id

#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-${var.env_deploy}-igw"
#   })
# }

#--------------------------------------------------------------
# Public Subnets (ALB, NAT Gateway, Bastion)
#--------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = {
    for i, az in var.avai_zones : az => i
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[each.value]
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-public-${each.value+1}"
    Tier = "public"
    # EKS ALB Controller: tự tìm public subnets để tạo internet-facing ALB
    "kubernetes.io/role/elb" = "1"
  })
}

#--------------------------------------------------------------
# Private Subnets (ECS Tasks, EKS Pods, EC2 Nodes)
#--------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = {
    for i, az in var.avai_zones : az => i
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[each.value]
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-private-${each.value+1}"
    Tier = "private"
    # EKS ALB Controller: tự tìm private subnets để tạo internal ALB
    "kubernetes.io/role/internal-elb" = "1"
  })
}

#--------------------------------------------------------------
# Data Subnets (RDS, ElastiCache, MSK, EFS) — No internet
#--------------------------------------------------------------
resource "aws_subnet" "data" {
  for_each = {
    for i, az in var.avai_zones : az => i
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.data_cidrs[each.value]
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-data-${each.value+1}"
    Tier = "data"
  })
}


#--------------------------------------------------------------
# Management Subnets — /27 (Bastion, VPN, CI Runners, Admin tools)
# Has NAT for updates/pulls, but isolated SG/NACL from workloads
#--------------------------------------------------------------
resource "aws_subnet" "mgmt" {
  for_each = {
    for i, az in var.avai_zones : az => i
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.mgmt_cidrs[each.value]
  availability_zone = each.key

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-mgmt-${each.value+1}"
    Tier = "mgmt"
  })
}

#--------------------------------------------------------------
# Internet Gateway
#--------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-igw"
  })
}

#--------------------------------------------------------------
# Elastic IPs for NAT Gateways
#--------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-eip-${var.avai_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

#--------------------------------------------------------------
# NAT Gateways
#--------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.avai_zones[count.index]].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-${var.avai_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

#--------------------------------------------------------------
# Route Table: Public (→ IGW)
#--------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.env_deploy}-rt-public"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public  
  subnet_id = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public-to-igw" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id
}

#--------------------------------------------------------------
# Route Tables: Private (→ NAT Gateway) — per AZ
#--------------------------------------------------------------
resource "aws_route_table" "private" {
  for_each = {
    for i, az in var.avai_zones : az => i
  }
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-private-${var.avai_zones[each.value]}"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route" "private" {
  for_each = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : each.key].id
}

#--------------------------------------------------------------
# Route Tables: Data (local only — NO internet access)
#--------------------------------------------------------------
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-data"
  })
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}