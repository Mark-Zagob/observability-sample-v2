#--------------------------------------------------------------
# Shared Environment - Main
# Wire modules vào đây, mỗi lần thêm module mới sẽ thêm 1 block
#--------------------------------------------------------------

#--------------------------------------------------------------
# Module 1: Network (VPC, Subnets, NAT, VPC Endpoints, Flow Logs)
#--------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_cidr     = var.vpc_cidr

  # Subnet CIDRs: tự tính bằng cidrsubnet() từ vpc_cidr
  # → 10.0.0.0/16 → public: .1-.3, private: .11-.13, data: .21-.23

  # NAT Gateway: true = 1 NAT (save $2/day), false = 3 NAT (HA)
  single_nat_gateway = var.single_nat_gateway

  # VPC Flow Logs: ghi network traffic vào CloudWatch
  enable_flow_logs = var.enable_flow_logs

  # Interface Endpoints: tốn phí, chỉ bật khi test
  enable_interface_endpoints = var.enable_interface_endpoints

  common_tags = {
    Module = "network"
  }
}

#--------------------------------------------------------------
# Module 2: Security (SG, IAM) — sẽ thêm sau
#--------------------------------------------------------------
# module "security" {
#   source = "../../modules/security"
#   ...
# }

#--------------------------------------------------------------
# Module 3: Data (RDS, Redis, MSK) — sẽ thêm sau
#--------------------------------------------------------------
# module "data" {
#   source = "../../modules/data"
#   ...
# }
