#--------------------------------------------------------------
# Dev Environment — Main
# Terraform Cloud backend — chỉ gọi network module để test TFC
#--------------------------------------------------------------

#--------------------------------------------------------------
# Module 1: Network (VPC, Subnets, NAT, Flow Logs)
#--------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_cidr     = var.vpc_cidr

  single_nat_gateway = var.single_nat_gateway
  enable_flow_logs   = var.enable_flow_logs

  common_tags = {
    Module = "network"
  }
}
