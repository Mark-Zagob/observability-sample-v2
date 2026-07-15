#--------------------------------------------------------------
# AMP — Amazon Managed Prometheus
#--------------------------------------------------------------
# Phase 1.5: Metrics storage cho ADOT sidecar remote write.
#--------------------------------------------------------------

module "amp" {
  source = "../../modules/observability/amp"

  project_name     = var.project_name
  environment      = var.environment
  sns_critical_arn = module.alerting.sns_critical_arn

  # Lab: 10,000 active series. Production: tăng lên 100,000+.
  active_series_threshold = var.environment == "prod" ? 100000 : 10000

  common_tags = {
    Module = "observability"
    Plane  = "Control"
  }
}

#--------------------------------------------------------------
# Attach AMP RemoteWrite policy → ECS Task Role
#--------------------------------------------------------------
# Ownership boundary: `security` module owns the ECS Task Role,
# `amp` module owns the RemoteWrite policy. Attachment lives here
# (caller) — không module nào ghi trực tiếp vào resource của module kia.
resource "aws_iam_role_policy_attachment" "ecs_task_amp_remote_write" {
  role       = module.security.ecs_task_role_name
  policy_arn = module.amp.remote_write_policy_arn
}

#--------------------------------------------------------------
# Attach KMS Access for AMP CMK → ECS Task Role
#--------------------------------------------------------------
# 🛡️ FIX: AMP workspace được mã hóa bằng KMS CMK.
# Khi ADOT sidecar remote write, AMP cần mượn IAM Task Role
# để gọi kms:GenerateDataKey. Nếu thiếu quyền này, ADOT nhận
# 403 Forbidden và drop toàn bộ metrics (Silent Data Loss).
#
# Boundary: `observability/amp` module sở hữu KMS Key,
# `security` module sở hữu Task Role.
# Attachment sống ở đây (caller) để tránh circular dependency.
#--------------------------------------------------------------
resource "aws_iam_role_policy" "ecs_task_amp_kms_access" {
  name = "${var.project_name}-${var.environment}-ecs-task-amp-kms"
  role = module.security.ecs_task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAMPKMSUsage"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = module.amp.kms_key_arn
      }
    ]
  })
}
