#--------------------------------------------------------------
# AMP — Amazon Managed Prometheus
#--------------------------------------------------------------
# Phase 1.5: Metrics storage cho ADOT sidecar remote write.
#--------------------------------------------------------------

module "amp" {
  source = "../../modules/observability/amp"

  project_name       = var.project_name
  environment        = var.environment
  ecs_task_role_name = module.security.ecs_task_role_name
  sns_critical_arn   = module.alerting.sns_critical_arn

  # Lab: 10,000 active series. Production: tăng lên 100,000+.
  active_series_threshold = var.environment == "prod" ? 100000 : 10000

  common_tags = {
    Module = "observability"
    Plane  = "Control"
  }
}
