#--------------------------------------------------------------
# Example: Complete Network Module Usage
#--------------------------------------------------------------
# This example shows a production-ready deployment of the
# network module with all options configured.
#
# Usage:
#   cd examples/complete
#   terraform init
#   terraform plan
#   terraform apply
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "example"
      ManagedBy   = "terraform"
    }
  }
}

#--------------------------------------------------------------
# Network Module
#--------------------------------------------------------------
module "network" {
  source = "../../"

  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count

  # NAT Gateway: true = 1 NAT (cost-saving), false = 1 per AZ (HA)
  single_nat_gateway = var.single_nat_gateway

  # VPC Flow Logs
  enable_flow_logs         = true
  flow_logs_retention_days = 7

  common_tags = {
    Module = "network"
  }
}

#--------------------------------------------------------------
# VPC Endpoints Module (optional, uncomment when ready)
#--------------------------------------------------------------
# module "vpc_endpoints" {
#   source = "../../../vpc-endpoints"
#
#   project_name = var.project_name
#   aws_region   = var.aws_region
#   vpc_id       = module.network.vpc_id
#   vpc_cidr     = module.network.vpc_cidr_block
#
#   route_table_ids = concat(
#     [module.network.public_route_table_id],
#     values(module.network.private_route_table_ids),
#     values(module.network.mgmt_route_table_ids),
#     [module.network.data_route_table_id]
#   )
#
#   enable_interface_endpoints = false
#   private_subnet_ids         = module.network.private_subnet_ids
#
#   common_tags = {
#     Module = "vpc-endpoints"
#   }
# }
