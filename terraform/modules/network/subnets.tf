#--------------------------------------------------------------
# Public Subnets — /24 (ALB, NAT Gateway)
#--------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.az_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[each.key]
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                     = "${var.project_name}-public-${each.value}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

#--------------------------------------------------------------
# Private Subnets — /20 (ECS Tasks, EKS Pods, EC2 Nodes)
# Biggest subnets: EKS VPC CNI consumes 1 IP per pod
#--------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[each.key]
  availability_zone = each.value

  tags = merge(var.common_tags, {
    Name                              = "${var.project_name}-private-${each.value}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

#--------------------------------------------------------------
# Data Subnets — /26 (RDS, ElastiCache, MSK, EFS)
# No internet access — isolated tier
#--------------------------------------------------------------
resource "aws_subnet" "data" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs_v2[each.key]
  availability_zone = each.value

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-data-${each.value}"
    Tier = "data"
  })
}

#--------------------------------------------------------------
# Management Subnets — /27 (Bastion, VPN, CI Runners)
# Has NAT for updates/pulls, but isolated SG/NACL from workloads
#--------------------------------------------------------------
resource "aws_subnet" "mgmt" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.mgmt_cidrs[each.key]
  availability_zone = each.value

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-mgmt-${each.value}"
    Tier = "mgmt"
  })
}
