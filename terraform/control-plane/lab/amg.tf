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

  common_tags = {
    Module = "observability"
    Plane  = "Control"
  }
}

#--------------------------------------------------------------
# Grafana Provider — Data Source Provisioning
#--------------------------------------------------------------
# Tương đương on-prem: grafana/provisioning/datasources/*.yml
# AWS:                  Grafana Terraform Provider resources
#
# Data sources sử dụng fixed UIDs để dashboard JSON reference.
#
# ⚠️ CHICKEN-AND-EGG: provider "grafana" phụ thuộc module.amg.* output
# (chỉ có giá trị thật SAU KHI module.amg đã apply). Lần đầu apply
# workspace mới (state trống) PHẢI chạy 2-phase:
#   1) terraform apply -target=module.amg
#   2) terraform apply
# Chi tiết + giải pháp production (tách state): docs/GRAFANA_PROVIDER_BOOTSTRAP.md
#--------------------------------------------------------------

provider "grafana" {
  url  = "https://${module.amg.workspace_endpoint}"
  auth = module.amg.service_account_token
}

# Prometheus (AMP) — tương đương provisioning/datasources/prometheus.yml
resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Amazon Managed Prometheus"
  uid        = "amp-datasource"
  is_default = true

  url                = module.amp.prometheus_endpoint
  basic_auth_enabled = false

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigV4Auth     = true
    sigV4AuthType = "workspace-iam-role"
    sigV4Region   = var.aws_region
    timeInterval  = "15s"

    exemplarTraceIdDestinations = [{
      name          = "trace_id"
      datasourceUid = "xray-datasource"
    }]
  })
}

# X-Ray — tương đương provisioning/datasources/tempo.yml
resource "grafana_data_source" "xray" {
  type = "grafana-x-ray-datasource"
  name = "AWS X-Ray"
  uid  = "xray-datasource"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "workspace-iam-role"
  })
}

# CloudWatch — tương đương provisioning/datasources/loki.yml
resource "grafana_data_source" "cloudwatch" {
  type = "cloudwatch"
  name = "Amazon CloudWatch"
  uid  = "cloudwatch-datasource"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "workspace-iam-role"
  })
}
