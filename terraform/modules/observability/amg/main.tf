#--------------------------------------------------------------
# Main — observability/amg
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  tags = merge(var.common_tags, {
    Module      = "observability-amg"
    Plane       = "Control"
    Environment = var.environment
    Project     = var.project_name
  })
}

#--------------------------------------------------------------
# 1. AMG Workspace
#--------------------------------------------------------------
resource "aws_grafana_workspace" "this" {
  name                     = "${local.name_prefix}-amg"
  description              = "Observability dashboard for ${var.project_name} ${var.environment}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.this.arn
  grafana_version          = var.grafana_version

  data_sources = ["PROMETHEUS", "XRAY", "CLOUDWATCH"]

  tags = local.tags
}

#--------------------------------------------------------------
# 2. IAM Role — Grafana workspace assume role
#--------------------------------------------------------------
resource "aws_iam_role" "this" {
  name = "${local.name_prefix}-amg-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = local.tags
}

#--------------------------------------------------------------
# 2a. IAM Policy — AMP read (scoped to workspace ARN)
#--------------------------------------------------------------
resource "aws_iam_role_policy" "amp_read" {
  name = "${local.name_prefix}-amg-amp-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAMPRead"
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = [var.amp_workspace_arn]
      }
    ]
  })
}

#--------------------------------------------------------------
# 2b. IAM Policy — X-Ray read
#--------------------------------------------------------------
resource "aws_iam_role_policy" "xray_read" {
  name = "${local.name_prefix}-amg-xray-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowXRayRead"
        Effect = "Allow"
        Action = [
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries",
          "xray:BatchGetTraces",
          "xray:GetServiceGraph",
          "xray:GetTraceGraph",
          "xray:GetTraceSummaries",
          "xray:GetGroups",
          "xray:GetGroup",
          "xray:GetTimeSeriesServiceStatistics",
          "xray:GetInsightSummaries",
          "xray:GetInsight"
        ]
        Resource = ["*"] # X-Ray does not support resource-level permissions
      }
    ]
  })
}

#--------------------------------------------------------------
# 2c. IAM Policy — CloudWatch Logs + Metrics read
#--------------------------------------------------------------
resource "aws_iam_role_policy" "cloudwatch_read" {
  name = "${local.name_prefix}-amg-cloudwatch-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/ecs/*",
          "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/ecs/*:*"
        ]
      },
      {
        Sid    = "AllowCloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = ["*"] # CloudWatch Metrics does not support resource-level permissions
      }
    ]
  })
}

#--------------------------------------------------------------
# 3. SSO Admin Role Assignment (conditional)
#--------------------------------------------------------------
resource "aws_grafana_role_association" "admin" {
  count = var.admin_user_id != "" ? 1 : 0

  role         = "ADMIN"
  user_ids     = [var.admin_user_id]
  workspace_id = aws_grafana_workspace.this.id
}

#--------------------------------------------------------------
# 4. Service Account + Token — Grafana Provider authentication
#--------------------------------------------------------------
# Used by Grafana Terraform Provider to auto-configure data sources.
# Token does not expire (seconds_to_live = 0).

resource "aws_grafana_workspace_service_account" "terraform" {
  name         = "terraform-automation"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.this.id
}

resource "aws_grafana_workspace_service_account_token" "terraform" {
  name               = "terraform-token"
  service_account_id = aws_grafana_workspace_service_account.terraform.id
  seconds_to_live    = 0
  workspace_id       = aws_grafana_workspace.this.id
}

#--------------------------------------------------------------
# 5. SSM Parameters — Cross-plane discovery
#--------------------------------------------------------------
resource "aws_ssm_parameter" "workspace_id" {
  name  = "/${var.project_name}/${var.environment}/observability/amg_workspace_id"
  type  = "String"
  value = aws_grafana_workspace.this.id
  tags  = local.tags
}

resource "aws_ssm_parameter" "endpoint" {
  name  = "/${var.project_name}/${var.environment}/observability/amg_endpoint"
  type  = "String"
  value = aws_grafana_workspace.this.endpoint
  tags  = local.tags
}
