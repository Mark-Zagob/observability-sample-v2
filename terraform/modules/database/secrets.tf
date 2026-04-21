#--------------------------------------------------------------
# Database Module — Secrets Management
#--------------------------------------------------------------
# Pattern: random_password → Secrets Manager
# ECS tasks read secrets at runtime via Task Execution Role.
# Password NEVER appears in terraform.tfvars or env vars.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Generate a random password for the RDS master user
#--------------------------------------------------------------
resource "random_password" "db_master" {
  length  = 24
  special = true

  # RDS disallows these characters in master passwords
  override_special = "!#$%&*()-_=+[]{}|:,.<>?"

  # Lifecycle: don't regenerate on every apply
  lifecycle {
    ignore_changes = [length, special, override_special]
  }
}

#--------------------------------------------------------------
# Store the password in AWS Secrets Manager
#--------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_master_password" {
  name        = "${var.project_name}/${var.environment}/database/master-password"
  description = "RDS PostgreSQL master password for ${var.project_name} (${var.environment})"

  # Allow Terraform to delete the secret (no recovery window in lab)
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-db-master-password"
    Component = "database"
  })
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id = aws_secretsmanager_secret.db_master_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_master.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = var.db_name
    # Full connection string for convenience
    url = "postgresql://${var.db_username}:${urlencode(random_password.db_master.result)}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${var.db_name}"
  })
}
