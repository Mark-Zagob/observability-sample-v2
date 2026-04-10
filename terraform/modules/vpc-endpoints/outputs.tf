#--------------------------------------------------------------
# VPC Endpoints Module — Outputs
#--------------------------------------------------------------

# Gateway Endpoints
output "s3_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB Gateway Endpoint"
  value       = aws_vpc_endpoint.dynamodb.id
}

# Interface Endpoints
output "interface_endpoint_ids" {
  description = "Map of service name → Interface Endpoint ID"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "endpoints_security_group_id" {
  description = "Security Group ID for VPC Interface Endpoints (null if disabled)"
  value       = var.enable_interface_endpoints ? aws_security_group.vpc_endpoints[0].id : null
}
