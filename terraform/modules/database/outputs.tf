#--------------------------------------------------------------
# Database Module — Outputs
#--------------------------------------------------------------
# Consumed by:
#   - Compute module → endpoints for ECS task env vars
#   - Security module → secret ARN for IAM policies
#   - Observability → instance ID for dashboard references
#--------------------------------------------------------------

#--------------------------------------------------------------
# RDS Instance
#--------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "RDS PostgreSQL hostname (without port)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "rds_db_name" {
  description = "Database name"
  value       = aws_db_instance.postgres.db_name
}

output "rds_instance_id" {
  description = "RDS instance identifier (for monitoring references)"
  value       = aws_db_instance.postgres.identifier
}

output "rds_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.postgres.arn
}

#--------------------------------------------------------------
# Secrets Manager
#--------------------------------------------------------------

output "db_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret (auto-rotated every 7 days)"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "db_secret_status" {
  description = "Status of the RDS-managed secret (Active = healthy)"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_status
}

#--------------------------------------------------------------
# SSM Parameter ARNs (for IAM policy construction)
#--------------------------------------------------------------

output "ssm_parameter_arns" {
  description = "Map of SSM parameter ARNs for IAM policy construction"
  value = {
    endpoint   = aws_ssm_parameter.db_endpoint.arn
    host       = aws_ssm_parameter.db_host.arn
    port       = aws_ssm_parameter.db_port.arn
    name       = aws_ssm_parameter.db_name.arn
    username   = aws_ssm_parameter.db_username.arn
    secret_arn = aws_ssm_parameter.db_secret_arn.arn
  }
}

output "ssm_parameter_prefix" {
  description = "SSM parameter path prefix for wildcard IAM policies"
  value       = "/${var.project_name}/${var.environment}/database"
}

#--------------------------------------------------------------
# Monitoring
#--------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for RDS PostgreSQL logs"
  value       = aws_cloudwatch_log_group.rds_postgres.name
}

#--------------------------------------------------------------
# KMS
#--------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "kms_key_id" {
  description = "ID of the KMS CMK"
  value       = aws_kms_key.rds.key_id
}

output "kms_alias_name" {
  description = "KMS key alias name"
  value       = aws_kms_alias.rds.name
}

#--------------------------------------------------------------
# Read Replicas
#--------------------------------------------------------------

output "replica_endpoints" {
  description = "List of read replica endpoints (host:port)"
  value       = [for r in aws_db_instance.read_replica : r.endpoint]
}

output "replica_addresses" {
  description = "List of read replica hostnames (without port)"
  value       = [for r in aws_db_instance.read_replica : r.address]
}

output "replica_instance_ids" {
  description = "List of read replica instance identifiers"
  value       = [for r in aws_db_instance.read_replica : r.identifier]
}
