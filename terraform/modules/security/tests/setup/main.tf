#--------------------------------------------------------------
# Security Module — Test Helper: Minimal VPC
#--------------------------------------------------------------
# Creates a bare VPC for security module integration tests.
# This is NOT the network module — just enough to satisfy
# vpc_id and vpc_cidr_block inputs.
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
  default = "10.98.0.0/16"
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

output "vpc_id" {
  value = aws_vpc.test.id
}

output "vpc_cidr_block" {
  value = aws_vpc.test.cidr_block
}
