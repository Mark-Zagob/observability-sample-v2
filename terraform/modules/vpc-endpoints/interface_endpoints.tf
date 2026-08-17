#--------------------------------------------------------------
# VPC Endpoints Module — Interface Endpoints
#--------------------------------------------------------------
# Interface Endpoints create ENIs in private subnets with
# private IPs. AWS services become accessible via private DNS
# without routing through NAT Gateway or Internet.
#
# Cost: ~$0.01/hr per endpoint per AZ ($7.2/month per AZ)
#       + $0.01/GB data processed
#
# Example with 2 AZs, 7 endpoints:
#   7 × 2 × $7.2 = ~$100.80/month (fixed)
#   + data transfer (variable)
#
# Toggle: enable_interface_endpoints = false for dev/lab
#         enable_interface_endpoints = true  for production
#
# Reference: AWS Well-Architected SEC05-BP02, COST06-BP01
#--------------------------------------------------------------


########################################################################
# Security Group — Interface Endpoints
########################################################################
# All Interface Endpoints share a single SG that allows
# HTTPS (443) from VPC CIDR. This is secure because:
#   - Endpoints only speak HTTPS (TLS-encrypted)
#   - Source is restricted to VPC CIDR (not 0.0.0.0/0)
#   - No egress needed (endpoints are service-side, not client-side)
########################################################################

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name_prefix = "${var.project_name}-vpce-"
  description = "Allow HTTPS from VPC to Interface VPC Endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-vpce"
    Tier = "infrastructure"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: HTTPS from VPC (all tiers need endpoint access)
resource "aws_security_group_rule" "vpce_ingress_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  type              = "ingress"
  description       = "HTTPS from VPC to Interface Endpoints"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = [var.vpc_cidr]
}

# No egress rule needed — Interface Endpoints are service-side.
# AWS handles the response traffic internally.
# By using separate aws_security_group_rule (not inline),
# the default allow-all egress is removed → zero egress = most secure.


########################################################################
# Interface Endpoints — Per-Service ENIs
########################################################################

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(var.interface_endpoint_services) : toset([])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-vpce-${replace(each.key, ".", "-")}"
    Service = each.key
    Type    = "interface"
  })

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_ids) > 0
      error_message = "private_subnet_ids must not be empty when enable_interface_endpoints is true. Interface Endpoints require at least one subnet for ENI placement."
    }
  }
}
