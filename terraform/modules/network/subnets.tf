#--------------------------------------------------------------
# Public Subnets — /24 (ALB, NAT Gateway)
#--------------------------------------------------------------
#checkov:skip=CKV_AWS_130:Public subnets require public IPs for NAT Gateway and ALB. Private/data subnets have map_public_ip_on_launch=false.
resource "aws_subnet" "public" {
  for_each = local.az_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[each.key]
  availability_zone       = each.value
  map_public_ip_on_launch = false # ✅ Explicit control, no auto-assign

  tags = merge(var.common_tags, {
    Name                     = "${var.project_name}-public-${each.value}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

#--------------------------------------------------------------
# Private Subnets — /20 (ECS Tasks, EKS Pods, EC2 Nodes, Bastion)
# Biggest subnets: EKS VPC CNI consumes 1 IP per pod
# Bastion host now lives here (SSM Session Manager, no SSH)
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
# Data Subnets — /24 (RDS, ElastiCache, MSK, EFS, OpenSearch)
# No internet access — isolated tier
# Increased from /26 to /24 for more IP headroom
#--------------------------------------------------------------
resource "aws_subnet" "data" {
  for_each = local.az_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[each.key]
  availability_zone = each.value

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-data-${each.value}"
    Tier = "data"
  })
}