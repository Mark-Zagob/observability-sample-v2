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
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_master_password.name
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
