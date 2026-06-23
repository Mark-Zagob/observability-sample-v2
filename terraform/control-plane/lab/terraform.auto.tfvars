#--------------------------------------------------------------
# Shared Environment - Values cho lab
#--------------------------------------------------------------

project_name = "obs"
aws_region   = "ap-southeast-2"
environment  = "lab"

# Network
vpc_cidr           = "10.0.0.0/16"
single_nat_gateway = true # 1 NAT = ~$1/day, 3 NAT = ~$3/day
enable_flow_logs   = true # Bật để học network debugging
# VPC Endpoints (uncomment khi bật module vpc-endpoints)
# enable_interface_endpoints = false
