#--------------------------------------------------------------
# Database Module — SSM Parameter Store
#--------------------------------------------------------------
# Store non-secret configuration for ECS tasks to discover.
# ECS containers read these at startup via Task Role permissions.
# Pattern: /project/env/component/key
#
# All parameters use SecureString (KMS encrypted) for consistency,
# even non-sensitive values like port numbers.
# CKV2_AWS_34: Ensure AWS SSM Parameter is Encrypted
#--------------------------------------------------------------

resource "aws_ssm_parameter" "db_endpoint" {
  name        = "/${var.project_name}/${var.environment}/database/endpoint"
  description = "RDS PostgreSQL endpoint (host:port)"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = aws_db_instance.postgres.endpoint

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-endpoint"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_host" {
  name        = "/${var.project_name}/${var.environment}/database/host"
  description = "RDS PostgreSQL hostname"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = aws_db_instance.postgres.address

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-host"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_port" {
  name        = "/${var.project_name}/${var.environment}/database/port"
  description = "RDS PostgreSQL port"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = tostring(aws_db_instance.postgres.port)

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-port"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/${var.project_name}/${var.environment}/database/name"
  description = "RDS PostgreSQL database name"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = var.db_name

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-name"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_username" {
  name        = "/${var.project_name}/${var.environment}/database/username"
  description = "RDS PostgreSQL master username"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = var.db_username

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-username"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_secret_arn" {
  name        = "/${var.project_name}/${var.environment}/database/secret-arn"
  description = "ARN of RDS-managed Secrets Manager secret (auto-rotated)"
  type        = "SecureString"
  key_id      = aws_kms_key.rds.arn
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-secret-arn"
    Component = "database"
  })
}
