#--------------------------------------------------------------
# Example Outputs — demonstrates module composition
#--------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "data_subnet_ids" {
  description = "Data subnet IDs"
  value       = module.network.data_subnet_ids
}

output "mgmt_subnet_ids" {
  description = "Management subnet IDs"
  value       = module.network.mgmt_subnet_ids
}

output "nat_public_ips" {
  description = "NAT Gateway public IPs"
  value       = module.network.nat_public_ips
}

output "availability_zones" {
  description = "AZs used"
  value       = module.network.availability_zones
}
