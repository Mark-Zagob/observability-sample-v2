#--------------------------------------------------------------
# Module: observability/amp — Amazon Managed Prometheus
#--------------------------------------------------------------
# Tạo AMP workspace cho Prometheus-compatible metrics storage.
# ADOT Sidecar (data-plane) push metrics via RemoteWrite API.
#
# Usage:
#   module "amp" {
#     source             = "../../modules/observability/amp"
#     project_name       = "obs"
#     environment        = "lab"
#     ecs_task_role_name = module.security.ecs_task_role_name
#     sns_critical_arn   = module.alerting.sns_critical_arn
#   }
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
