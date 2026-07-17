#--------------------------------------------------------------
# Grafana Config — Data Sources
#--------------------------------------------------------------
# Tương đương on-prem: grafana/provisioning/datasources/*.yml
# AWS:                  Grafana Terraform Provider resources
#
# Data sources sử dụng fixed UIDs để dashboard JSON reference
# được ổn định across environments.
#--------------------------------------------------------------

# AMP endpoint từ SSM (đã export bởi modules/observability/amp)
data "aws_ssm_parameter" "amp_endpoint" {
  name = "/${var.project_name}/${var.environment}/observability/amp_endpoint"
}

#--------------------------------------------------------------
# 1. Prometheus (AMP)
#--------------------------------------------------------------
# Tương đương provisioning/datasources/prometheus.yml
resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Amazon Managed Prometheus"
  uid        = "amp-datasource"
  is_default = true

  url                = data.aws_ssm_parameter.amp_endpoint.value
  basic_auth_enabled = false

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigV4Auth     = true
    # "default" = dùng IAM execution role của AMG workspace (không phải "workspace-iam-role" — đó là UI label)
    sigV4AuthType = "default"
    sigV4Region   = var.aws_region
    timeInterval  = "15s"

    # Reference trực tiếp resource attribute (không dùng string literal
    # "xray-datasource") để Terraform build đúng dependency graph —
    # đảm bảo grafana_data_source.xray được tạo trước khi exemplar
    # link tới nó, tránh broken link ở lần apply đầu tiên.
    exemplarTraceIdDestinations = [{
      name          = "trace_id"
      datasourceUid = grafana_data_source.xray.uid
    }]
  })
}

#--------------------------------------------------------------
# 2. X-Ray (Traces)
#--------------------------------------------------------------
# Tương đương provisioning/datasources/tempo.yml (tracing backend)
resource "grafana_data_source" "xray" {
  type = "grafana-x-ray-datasource"
  name = "AWS X-Ray"
  uid  = "xray-datasource"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "default"
  })
}

#--------------------------------------------------------------
# 3. CloudWatch (Logs + Metrics)
#--------------------------------------------------------------
# Tương đương provisioning/datasources/loki.yml (logs backend)
resource "grafana_data_source" "cloudwatch" {
  type = "cloudwatch"
  name = "Amazon CloudWatch"
  uid  = "cloudwatch-datasource"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "default"
  })
}

#--------------------------------------------------------------
# 4. Dashboards
#--------------------------------------------------------------
# Tương đương on-prem: grafana/dashboards/Application/*.json
# AWS:                  grafana_dashboard resources (Dashboard as Code)
#
# Dashboard JSON dùng templatefile() để inject giá trị động
# (AMP workspace ID) — survive across terraform destroy/apply cycles.
#--------------------------------------------------------------

data "aws_ssm_parameter" "amp_workspace_id" {
  name = "/${var.project_name}/${var.environment}/observability/amp_workspace_id"
}

resource "grafana_dashboard" "pod1_illumination" {
  config_json = templatefile("${path.module}/dashboards/pod1-illumination.json.tftpl", {
    amp_workspace_id = data.aws_ssm_parameter.amp_workspace_id.value
  })
  overwrite = true
}
