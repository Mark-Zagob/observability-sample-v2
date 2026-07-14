#--------------------------------------------------------------
# Module: observability/amp — Amazon Managed Prometheus
#--------------------------------------------------------------
# Tạo AMP workspace cho Prometheus-compatible metrics storage,
# mã hóa at-rest bằng KMS CMK riêng (xem kms.tf).
# ADOT Sidecar (data-plane) push metrics via RemoteWrite API.
#
# Module CHỈ tạo policy (aps:RemoteWrite) — không tự attach vào
# ECS Task Role. Caller phải tự attach qua aws_iam_role_policy_attachment
# (xem output `remote_write_policy_arn`).
#
# Usage:
#   module "amp" {
#     source           = "../../modules/observability/amp"
#     project_name     = "obs"
#     environment      = "lab"
#     sns_critical_arn = module.alerting.sns_critical_arn
#   }
#
#   resource "aws_iam_role_policy_attachment" "ecs_task_amp_remote_write" {
#     role       = module.security.ecs_task_role_name
#     policy_arn = module.amp.remote_write_policy_arn
#   }
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.31 cần thiết để aws_prometheus_workspace hỗ trợ kms_key_arn
      # (customer-managed KMS key encryption at-rest).
      version = ">= 5.31.0"
    }
  }
}
