#--------------------------------------------------------------
# AMG — Amazon Managed Grafana
#--------------------------------------------------------------
# Phase 1.5: Observability dashboard (tương đương self-hosted Grafana).
# Pre-req: IAM Identity Center phải enabled trong AWS Organization.
#--------------------------------------------------------------

module "amg" {
  source = "../../modules/observability/amg"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  amp_workspace_arn = module.amp.workspace_arn
  admin_user_id     = var.amg_admin_user_id

  # Sandbox là member account trong Org — SSO instance thuộc management
  # account, ListInstances trả empty từ đây. SSO vẫn hoạt động cho AMG.
  skip_sso_check = true

  common_tags = {
    Module = "observability"
    Plane  = "Control"
  }
}

#--------------------------------------------------------------
# Grafana data sources (AMP, X-Ray, CloudWatch) đã tách sang
# state riêng: control-plane/lab-grafana/
#
# Lý do: provider "grafana" cần module.amg.* output → circular
# dependency khi apply lần đầu. Tách state giải quyết triệt để.
# Chi tiết: docs/GRAFANA_PROVIDER_BOOTSTRAP.md
#--------------------------------------------------------------
