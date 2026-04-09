#--------------------------------------------------------------
# Shared Environment - Values cho lab
#--------------------------------------------------------------

project_name = "obs-lab"
aws_region   = "ap-southeast-2"

# Network
vpc_cidr           = "10.0.0.0/16"
single_nat_gateway = true   # 1 NAT = ~$1/day, 3 NAT = ~$3/day
enable_flow_logs   = true   # Bật để học network debugging
enable_interface_endpoints = false  # Tắt mặc định, bật khi cần test
