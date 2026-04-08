#--------------------------------------------------------------
# Shared Environment - Outputs
# Các compute environments (phase-8a, 8b, ...) sẽ read outputs này
# thông qua terraform_remote_state hoặc output files
#--------------------------------------------------------------

# Network outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
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

output "availability_zones" {
  description = "Availability zones"
  value       = module.network.availability_zones
}

output "nat_public_ips" {
  description = "NAT Gateway public IPs"
  value       = module.network.nat_public_ips
}
