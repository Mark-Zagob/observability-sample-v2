#--------------------------------------------------------------
# Network Module - Outputs
#--------------------------------------------------------------

# VPC
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnets - IDs
output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "List of data subnet IDs"
  value       = aws_subnet.data[*].id
}

output "mgmt_subnet_ids" {
  description = "List of management subnet IDs"
  value       = aws_subnet.mgmt[*].id
}

# Subnets - CIDRs
output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "data_subnet_cidrs" {
  description = "List of data subnet CIDR blocks"
  value       = aws_subnet.data[*].cidr_block
}

output "mgmt_subnet_cidrs" {
  description = "List of management subnet CIDR blocks"
  value       = aws_subnet.mgmt[*].cidr_block
}

# AZs
output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

# NAT Gateway
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "List of NAT Gateway public IPs"
  value       = aws_eip.nat[*].public_ip
}

# Internet Gateway
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# VPC Endpoints
output "s3_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB Gateway Endpoint"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security Group ID for VPC Interface Endpoints (null if disabled)"
  value       = var.enable_interface_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}
