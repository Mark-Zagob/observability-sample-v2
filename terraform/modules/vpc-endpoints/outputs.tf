#--------------------------------------------------------------
# VPC Endpoints Module — Outputs
#--------------------------------------------------------------
# Consumed by:
#   - Network module (S3 endpoint for VPC Flow Logs export)
#   - Compute module (ECR, CW Logs endpoints for ECS)
#   - Security audit (verify endpoints exist)
#--------------------------------------------------------------

#--------------------------------------------------------------
# Gateway Endpoint IDs
#--------------------------------------------------------------

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint (empty string if disabled)"
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : ""
}

output "s3_endpoint_prefix_list_id" {
  description = "Prefix list ID for S3 Gateway Endpoint (use in SG rules to restrict S3 egress)"
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].prefix_list_id : ""
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB Gateway Endpoint (empty string if disabled)"
  value       = var.enable_dynamodb_endpoint ? aws_vpc_endpoint.dynamodb[0].id : ""
}

output "dynamodb_endpoint_prefix_list_id" {
  description = "Prefix list ID for DynamoDB Gateway Endpoint"
  value       = var.enable_dynamodb_endpoint ? aws_vpc_endpoint.dynamodb[0].prefix_list_id : ""
}

#--------------------------------------------------------------
# Interface Endpoint IDs
#--------------------------------------------------------------

output "interface_endpoint_ids" {
  description = "Map of service name → Interface Endpoint ID"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "interface_endpoint_dns" {
  description = "Map of service name → primary DNS entry"
  value = {
    for k, v in aws_vpc_endpoint.interface : k => try(v.dns_entry[0].dns_name, "")
  }
}

#--------------------------------------------------------------
# Security Group
#--------------------------------------------------------------

output "endpoints_security_group_id" {
  description = "Security Group ID for VPC Interface Endpoints (empty string if disabled)"
  value       = var.enable_interface_endpoints ? aws_security_group.vpc_endpoints[0].id : ""
}

#--------------------------------------------------------------
# Summary Maps (for bulk operations / audit)
#--------------------------------------------------------------

output "gateway_endpoints" {
  description = "Map of gateway endpoint names to IDs"
  value = merge(
    var.enable_s3_endpoint ? { s3 = aws_vpc_endpoint.s3[0].id } : {},
    var.enable_dynamodb_endpoint ? { dynamodb = aws_vpc_endpoint.dynamodb[0].id } : {}
  )
}

output "all_endpoint_ids" {
  description = "Flat list of ALL endpoint IDs (gateway + interface) for audit"
  value = concat(
    var.enable_s3_endpoint ? [aws_vpc_endpoint.s3[0].id] : [],
    var.enable_dynamodb_endpoint ? [aws_vpc_endpoint.dynamodb[0].id] : [],
    [for v in aws_vpc_endpoint.interface : v.id]
  )
}
