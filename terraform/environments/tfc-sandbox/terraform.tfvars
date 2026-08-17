#--------------------------------------------------------------
# Dev Environment - Values
#--------------------------------------------------------------

project_name = "obs"
aws_region   = "ap-southeast-2"
environment  = "dev"

# Network — same CIDR structure but different range to avoid conflict
vpc_cidr           = "10.1.0.0/16"
single_nat_gateway = true
enable_flow_logs   = true
