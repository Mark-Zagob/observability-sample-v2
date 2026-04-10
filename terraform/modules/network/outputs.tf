#--------------------------------------------------------------
# Network Module — Outputs
#--------------------------------------------------------------

# VPC
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

# Subnets — IDs (lists for downstream compatibility)
output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.public[k].id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.private[k].id]
}

output "data_subnet_ids" {
  description = "List of data subnet IDs"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.data[k].id]
}

output "mgmt_subnet_ids" {
  description = "List of management subnet IDs"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.mgmt[k].id]
}

# Subnets — CIDRs
output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.public[k].cidr_block]
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.private[k].cidr_block]
}

output "data_subnet_cidrs" {
  description = "List of data subnet CIDR blocks"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.data[k].cidr_block]
}

output "mgmt_subnet_cidrs" {
  description = "List of management subnet CIDR blocks"
  value       = [for k in sort(keys(local.az_map)) : aws_subnet.mgmt[k].cidr_block]
}

# Subnets — Maps (for_each-friendly access)
output "public_subnets" {
  description = "Map of AZ key → public subnet attributes"
  value       = { for k, v in aws_subnet.public : k => { id = v.id, cidr_block = v.cidr_block, availability_zone = v.availability_zone } }
}

output "private_subnets" {
  description = "Map of AZ key → private subnet attributes"
  value       = { for k, v in aws_subnet.private : k => { id = v.id, cidr_block = v.cidr_block, availability_zone = v.availability_zone } }
}

# AZs
output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

output "az_map" {
  description = "Map of AZ short key to full AZ name"
  value       = local.az_map
}

# NAT Gateway
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = [for k in sort(keys(local.nat_az_map)) : aws_nat_gateway.this[k].id]
}

output "nat_public_ips" {
  description = "List of NAT Gateway public IPs"
  value       = [for k in sort(keys(local.nat_az_map)) : aws_eip.nat[k].public_ip]
}

# Internet Gateway
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

# Route Tables (for external module consumption)
output "mgmt_route_table_ids" {
  description = "Map of AZ key → management route table ID"
  value       = { for k, v in aws_route_table.mgmt : k => v.id }
}

output "private_route_table_ids" {
  description = "Map of AZ key → private route table ID"
  value       = { for k, v in aws_route_table.private : k => v.id }
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "data_route_table_id" {
  description = "ID of the data route table"
  value       = aws_route_table.data.id
}

