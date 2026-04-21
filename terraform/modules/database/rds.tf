#--------------------------------------------------------------
# Database Module — RDS PostgreSQL
#--------------------------------------------------------------

#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#--------------------------------------------------------------
# Locals
#--------------------------------------------------------------
locals {
  identifier = "${var.project_name}-${var.environment}-postgres"
}

#--------------------------------------------------------------
# Random suffix for final snapshot (prevent name collision on destroy)
#--------------------------------------------------------------
resource "random_id" "snapshot_suffix" {
  byte_length = 4
}

#--------------------------------------------------------------
# DB Subnet Group
#--------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${local.identifier}-subnet-group"
  description = "Subnet group for ${local.identifier} in data subnets"
  subnet_ids  = var.data_subnet_ids

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-subnet-group"
    Component = "database"
  })
}

#--------------------------------------------------------------
# Custom Parameter Group — PostgreSQL Tuning
#--------------------------------------------------------------
resource "aws_db_parameter_group" "postgres" {
  name        = "${local.identifier}-params"
  family      = "postgres16"
  description = "Custom parameters for ${local.identifier}"

  # Logging: log queries slower than 1 second
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Logging: log all DDL statements
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  # Connection: log disconnections for debugging
  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Performance: shared_buffers (25% of RAM is typical)
  # For db.t3.micro (1GB RAM) → 256MB is fine
  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/4}"
    apply_method = "pending-reboot"
  }

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-params"
    Component = "database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#--------------------------------------------------------------
# RDS PostgreSQL Instance
#--------------------------------------------------------------
resource "aws_db_instance" "postgres" {
  identifier = local.identifier

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.data_security_group_id]
  publicly_accessible    = false

  # Parameters
  parameter_group_name = aws_db_parameter_group.postgres.name

  # High Availability
  multi_az = var.multi_az

  # Backup
  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:05:00-Mon:06:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final-${random_id.snapshot_suffix.hex}"
  deletion_protection       = var.deletion_protection

  # Monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = var.environment == "prod" ? 731 : 7
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  monitoring_interval                   = var.enhanced_monitoring_interval
  monitoring_role_arn                   = var.enhanced_monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  # Security
  iam_database_authentication_enabled = true

  # Updates
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Lifecycle
  lifecycle {
    ignore_changes = [password]
  }

  tags = merge(var.common_tags, {
    Name        = local.identifier
    Component   = "database"
    Engine      = "postgres"
    Environment = var.environment
  })
}
