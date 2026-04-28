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

# Security outputs
output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = module.security.alb_security_group_id
}

output "application_security_group_id" {
  description = "Application Security Group ID"
  value       = module.security.application_security_group_id
}

output "data_security_group_id" {
  description = "Data tier Security Group ID"
  value       = module.security.data_security_group_id
}

output "ecs_task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = module.security.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = module.security.ecs_task_role_arn
}

# VPC Endpoints outputs
output "s3_endpoint_id" {
  description = "S3 Gateway Endpoint ID"
  value       = module.vpc_endpoints.s3_endpoint_id
}

output "s3_endpoint_prefix_list_id" {
  description = "S3 prefix list ID (for SG rules restricting egress to S3)"
  value       = module.vpc_endpoints.s3_endpoint_prefix_list_id
}

output "vpc_endpoints_security_group_id" {
  description = "Interface Endpoints Security Group ID"
  value       = module.vpc_endpoints.endpoints_security_group_id
}

# Database outputs
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = module.database.rds_endpoint
}

output "rds_arn" {
  description = "ARN of the RDS instance"
  value       = module.database.rds_arn
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed secret"
  value       = module.database.db_secret_arn
}

# Backup outputs
output "backup_vault_arn" {
  description = "Primary backup vault ARN"
  value       = module.backup.vault_arn
}

output "backup_vault_dr_arn" {
  description = "DR region backup vault ARN"
  value       = module.backup.vault_dr_arn
}

output "backup_plan_arn" {
  description = "Backup plan ARN"
  value       = module.backup.plan_arn
}

output "backup_sns_topic_arn" {
  description = "SNS topic ARN for backup notifications (reusable by other modules)"
  value       = module.backup.sns_topic_arn
}

output "backup_selection_tag" {
  description = "Tag key/value to add to resources for backup protection"
  value       = module.backup.selection_tag
}
