#--------------------------------------------------------------
# DML-only Application User (Least Privilege at DB level)
#--------------------------------------------------------------
# Master user (RDS managed secret) → Migration Plane only (DDL)
# app_user (this secret)           → App runtime only (DML)
#
# Production Parallel: DBA/Platform team creates this in production.
# Password in Terraform state (S3+KMS encrypted). For team ≥ 5,
# use Vault or Secrets Manager lifecycle management instead.
#--------------------------------------------------------------

resource "random_password" "app_user" {
  length  = 24
  special = true
  # URL-safe only: no $ ! @ : / ? # % (break bash expansion or connection strings)
  override_special = "-_=+()*"

  lifecycle {
    ignore_changes = [length, special, override_special]
  }
}

resource "aws_secretsmanager_secret" "app_user" {
  name        = "${var.project_name}/${var.environment}/database/app-user"
  description = "DML-only application user for ${local.identifier}"
  kms_key_id  = aws_kms_key.rds.arn
  # Prod: 30 ngày recovery (chuẩn compliance).
  # Non-prod: 0 = hard-delete ngay khi terraform destroy — tránh block
  # apply lại trong vòng 7 ngày với lỗi "already scheduled for deletion".
  # (Mặc định AWS là 7-30 ngày; 0 là giá trị đặc biệt rừ bắt buộc
  # để hard-delete). Khớp với contract test cho db_master_password.
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-app-user-secret"
    Component = "database"
    Privilege = "dml-only"
  })
}

resource "aws_secretsmanager_secret_version" "app_user" {
  secret_id = aws_secretsmanager_secret.app_user.id
  secret_string = jsonencode({
    username = "app_user"
    password = random_password.app_user.result
  })
}
