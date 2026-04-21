#--------------------------------------------------------------
# Database Module — Test Helper: VPC + Subnets + Security Group
#--------------------------------------------------------------
# Creates minimal infrastructure for database integration tests.
# This is NOT the network/security modules — just enough to
# satisfy vpc_id, data_subnet_ids, and data_security_group_id.
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
  default = "10.99.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

#--------------------------------------------------------------
# VPC
#--------------------------------------------------------------
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

#--------------------------------------------------------------
# Subnets (minimum 2 AZs for RDS subnet group)
#--------------------------------------------------------------
resource "aws_subnet" "data_a" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1) # 10.99.1.0/24
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-test-data-a"
    Environment = "integration-test"
    Ephemeral   = "true"
  }
}

resource "aws_subnet" "data_b" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2) # 10.99.2.0/24
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "${var.project_name}-test-data-b"
    Environment = "integration-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# Security Group (allow PostgreSQL from within VPC)
#--------------------------------------------------------------
resource "aws_security_group" "data" {
  name        = "${var.project_name}-test-data-sg"
  description = "Test SG for database integration tests"
  vpc_id      = aws_vpc.test.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_name}-test-data-sg"
    Environment = "integration-test"
    Ephemeral   = "true"
  }
}

#--------------------------------------------------------------
# Outputs
#--------------------------------------------------------------
output "vpc_id" {
  value = aws_vpc.test.id
}

output "data_subnet_ids" {
  value = [aws_subnet.data_a.id, aws_subnet.data_b.id]
}

output "data_security_group_id" {
  value = aws_security_group.data.id
}
