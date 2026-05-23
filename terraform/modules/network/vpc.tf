#--------------------------------------------------------------
# VPC
#--------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

#--------------------------------------------------------------
# Lock Default Security Group — CKV2_AWS_12
#--------------------------------------------------------------
# AWS auto-creates a default SG with allow-all rules.
# Lock it down: no ingress, no egress.
# → Forces explicit SG assignment for all resources.
# → Prevents accidental exposure via default SG.
#--------------------------------------------------------------
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  # No ingress or egress blocks = deny all traffic
  # Any resource using default SG → no network access

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-default-sg-DO-NOT-USE"
    Purpose = "locked-down-default"
  })
}

#--------------------------------------------------------------
# Internet Gateway
#--------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}
