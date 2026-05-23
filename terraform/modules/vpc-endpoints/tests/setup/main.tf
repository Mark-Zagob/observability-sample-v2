#--------------------------------------------------------------
# VPC Endpoints Test Helper — Minimal VPC + Route Table
#--------------------------------------------------------------
# Creates bare minimum resources needed to test VPC endpoints:
# - VPC (for endpoint creation)
# - Subnet (for interface endpoint ENI placement)
# - Route Table (for gateway endpoint route entries)
#--------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.97.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "test" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-test-vpc"
    Environment = "integration-test"
    Ephemeral   = "true"
  }
}

resource "aws_subnet" "test" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name      = "${var.project_name}-test-subnet"
    Ephemeral = "true"
  }
}

resource "aws_route_table" "test" {
  vpc_id = aws_vpc.test.id

  tags = {
    Name      = "${var.project_name}-test-rt"
    Ephemeral = "true"
  }
}

resource "aws_route_table_association" "test" {
  subnet_id      = aws_subnet.test.id
  route_table_id = aws_route_table.test.id
}

output "vpc_id" {
  value = aws_vpc.test.id
}

output "vpc_cidr" {
  value = aws_vpc.test.cidr_block
}

output "subnet_ids" {
  value = [aws_subnet.test.id]
}

output "route_table_ids" {
  value = [aws_route_table.test.id]
}
