#--------------------------------------------------------------
# Database Module — SSM Parameter Store
#--------------------------------------------------------------
# Store non-secret configuration for ECS tasks to discover.
# ECS containers read these at startup via Task Role permissions.
# Pattern: /project/env/component/key
#--------------------------------------------------------------

resource "aws_ssm_parameter" "db_endpoint" {
  name        = "/${var.project_name}/${var.environment}/database/endpoint"
  description = "RDS PostgreSQL endpoint (host:port)"
  type        = "String"
  value       = aws_db_instance.postgres.endpoint

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-endpoint"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_host" {
  name        = "/${var.project_name}/${var.environment}/database/host"
  description = "RDS PostgreSQL hostname"
  type        = "String"
  value       = aws_db_instance.postgres.address

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-host"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_port" {
  name        = "/${var.project_name}/${var.environment}/database/port"
  description = "RDS PostgreSQL port"
  type        = "String"
  value       = tostring(aws_db_instance.postgres.port)

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-port"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/${var.project_name}/${var.environment}/database/name"
  description = "RDS PostgreSQL database name"
  type        = "String"
  value       = var.db_name

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-name"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_username" {
  name        = "/${var.project_name}/${var.environment}/database/username"
  description = "RDS PostgreSQL master username"
  type        = "String"
  value       = var.db_username

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-username"
    Component = "database"
  })
}

resource "aws_ssm_parameter" "db_secret_arn" {
  name        = "/${var.project_name}/${var.environment}/database/secret-arn"
  description = "ARN of Secrets Manager secret containing DB credentials"
  type        = "String"
  value       = aws_secretsmanager_secret.db_master_password.arn

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-secret-arn"
    Component = "database"
  })
}
