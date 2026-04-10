#--------------------------------------------------------------
# VPC Endpoints Module — Main Resources
# Manages Gateway (S3, DynamoDB) and Interface Endpoints
# separately from the core network module.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Gateway Endpoints (FREE — S3 & DynamoDB)
#--------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-dynamodb"
  })
}

#--------------------------------------------------------------
# Interface Endpoints — Security Group
#--------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from VPC to Interface Endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_all" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

#--------------------------------------------------------------
# Interface Endpoints (OPTIONAL — costs ~$0.01/hr each)
#--------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(var.interface_endpoint_services) : toset([])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-${each.key}"
  })
}
