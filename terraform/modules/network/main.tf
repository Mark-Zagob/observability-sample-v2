#--------------------------------------------------------------
# Network Module - Production-Grade
# VPC, Subnets (4 tiers), IGW, NAT, VPC Endpoints, Flow Logs
#--------------------------------------------------------------

#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  nat_gateway_count = var.single_nat_gateway ? 1 : length(local.azs)

  #------------------------------------------------------------
  # Hierarchical CIDR Allocation — Production Layout
  #------------------------------------------------------------
  # Strategy: chia VPC /16 thành 4 blocks /18 (Level 1)
  #           rồi chia mỗi block thành subnets khác kích thước (Level 2)
  #
  # Tại sao 2 levels?
  # → cidrsubnet() tạo subnets CÙNG kích thước
  # → Muốn mixed sizes (/20, /24, /26, /27) phải chia blocks trước
  # → Blocks khác nhau KHÔNG BAO GIỜ overlap
  #
  # Toàn bộ derive từ var.vpc_cidr — không hardcode bất kỳ IP nào
  #------------------------------------------------------------

  # Level 1: Chia VPC thành 2 nửa (/17)
  # Nửa đầu: Private workloads (rất tốn IPs vì EKS pods)
  # Nửa sau: Tất cả các subnets khác và dành cho tương lai
  half_private = cidrsubnet(var.vpc_cidr, 1, 0)
  half_others  = cidrsubnet(var.vpc_cidr, 1, 1)

  # Level 2: Private subnets
  # Cắt 3 blocks /20 (4,096 IPs/AZ) từ half_private, còn lại 5 blocks /20 reserved
  private_cidrs = [for i in range(3) : cidrsubnet(local.half_private, 3, i)]

  # Level 3: Chia half_others thành các block /20
  others_blocks = [for i in range(8) : cidrsubnet(local.half_others, 3, i)]

  # Level 4: Tạo subnets từ các block của half_others
  # ┌─────────┬──────────────────┬─────────┬─────────┬──────────────────────┐
  # │ Tier    │ Block            │ newbits │ Size    │ IPs/AZ               │
  # ├─────────┼──────────────────┼─────────┼─────────┼──────────────────────┤
  # │ Public  │ others_blocks[0] │ +4      │ /24     │ 254   (ALB, NAT)     │
  # │ Data    │ others_blocks[1] │ +6      │ /26     │ 62    (RDS, Redis)   │
  # │ Mgmt    │ others_blocks[2] │ +7      │ /27     │ 30    (Bastion, VPN) │
  # └─────────┴──────────────────┴─────────┴─────────┴──────────────────────┘
  public_cidrs = [for i in range(3) : cidrsubnet(local.others_blocks[0], 4, i)] # /24
  data_cidrs   = [for i in range(3) : cidrsubnet(local.others_blocks[1], 6, i)] # /26
  mgmt_cidrs   = [for i in range(3) : cidrsubnet(local.others_blocks[2], 7, i)] # /27
}

#--------------------------------------------------------------
# VPC
#--------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

#--------------------------------------------------------------
# Internet Gateway
#--------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

#--------------------------------------------------------------
# Public Subnets — /24 (ALB, NAT Gateway)
#--------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                        = "${var.project_name}-public-${local.azs[count.index]}"
    Tier                        = "public"
    "kubernetes.io/role/elb"    = "1"
  })
}

#--------------------------------------------------------------
# Private Subnets — /20 (ECS Tasks, EKS Pods, EC2 Nodes)
# Biggest subnets: EKS VPC CNI consumes 1 IP per pod
#--------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.common_tags, {
    Name                              = "${var.project_name}-private-${local.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb"  = "1"
  })
}

#--------------------------------------------------------------
# Data Subnets — /26 (RDS, ElastiCache, MSK, EFS)
# No internet access — isolated tier
#--------------------------------------------------------------
resource "aws_subnet" "data" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.data_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-data-${local.azs[count.index]}"
    Tier = "data"
  })
}

#--------------------------------------------------------------
# Management Subnets — /27 (Bastion, VPN, CI Runners, Admin tools)
# Has NAT for updates/pulls, but isolated SG/NACL from workloads
#--------------------------------------------------------------
resource "aws_subnet" "mgmt" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.mgmt_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-mgmt-${local.azs[count.index]}"
    Tier = "mgmt"
  })
}

#--------------------------------------------------------------
# Elastic IPs for NAT Gateways
#--------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-eip-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

#--------------------------------------------------------------
# NAT Gateways
#--------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

#--------------------------------------------------------------
# Route Table: Public (→ IGW)
#--------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-public"
  })
}

resource "aws_route_table_association" "public" {
  count = length(local.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#--------------------------------------------------------------
# Route Tables: Private (→ NAT Gateway) — per AZ
#--------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-private-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(local.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
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
  count = length(local.azs)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

#--------------------------------------------------------------
# Route Tables: Mgmt (→ NAT Gateway) — same NAT as private
# Separate route tables enable future NACL/routing differences
#--------------------------------------------------------------
resource "aws_route_table" "mgmt" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-mgmt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "mgmt" {
  count = length(local.azs)

  subnet_id      = aws_subnet.mgmt[count.index].id
  route_table_id = aws_route_table.mgmt[count.index].id
}

#--------------------------------------------------------------
# VPC Gateway Endpoints (FREE)
#--------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.data.id],
    aws_route_table.mgmt[*].id
  )

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.data.id],
    aws_route_table.mgmt[*].id
  )

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-dynamodb"
  })
}

#--------------------------------------------------------------
# VPC Flow Logs
#--------------------------------------------------------------
resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        aws_cloudwatch_log_group.flow_logs[0].arn,
        "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
      ]
    }]
  })
}

#--------------------------------------------------------------
# VPC Interface Endpoints (OPTIONAL — costs ~$0.01/hr each)
#--------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(var.interface_endpoint_services) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-${each.key}"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from VPC to Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-sg"
  })
}
