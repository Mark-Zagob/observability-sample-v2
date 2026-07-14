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
