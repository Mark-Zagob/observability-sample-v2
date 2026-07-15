#--------------------------------------------------------------
# Main — observability/amg
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Prerequisite check: AMG dùng authentication_providers = ["AWS_SSO"],
# yêu cầu IAM Identity Center (SSO) đã được enable trong Organization.
#
# ⚠️ CAVEAT: data "aws_ssoadmin_instances" gọi sso-admin:ListInstances.
# Trong AWS Organization, SSO instance thuộc sở hữu management account
# (hoặc delegated admin). Member accounts (VD: sandbox) SỬ DỤNG SSO
# bình thường, nhưng ListInstances trả về empty list — gây false negative.
#
# Nếu account là member account trong Org đã có SSO, set:
#   skip_sso_check = true
data "aws_ssoadmin_instances" "current" {
  count = var.skip_sso_check ? 0 : 1
}

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
# permission_type = CUSTOMER_MANAGED: chúng ta tự quản lý IAM policies
# (amp_read, xray_read, cloudwatch_read bên dưới) thay vì để AWS
# tự sinh policy qua `data_sources`. Tránh duplicate/overlap IAM giữa
# 2 cơ chế (SERVICE_MANAGED sinh policy riêng + policy thủ công),
# giúp audit least-privilege dễ hơn.
resource "aws_grafana_workspace" "this" {
  name                     = "${local.name_prefix}-amg"
  description              = "Observability dashboard for ${var.project_name} ${var.environment}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.this.arn
  grafana_version          = var.grafana_version

  tags = local.tags

  lifecycle {
    # Chỉ check khi skip_sso_check = false (mặc định).
    # Khi skip = true, data source không tồn tại → condition luôn true.
    precondition {
      condition     = var.skip_sso_check || length(data.aws_ssoadmin_instances.current[0].arns) > 0
      error_message = "IAM Identity Center (AWS SSO) chưa được enable trong Account/Organization này. AMG với authentication_providers = [\"AWS_SSO\"] yêu cầu ít nhất 1 SSO instance. Nếu account là member trong Org đã có SSO, set skip_sso_check = true."
    }
  }
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
# 2d. IAM Policy — AMP KMS Decrypt (Fix bẫy CMK)
#--------------------------------------------------------------
# AMP metrics được mã hóa bằng CMK. AMG cần kms:Decrypt để đọc.
# Thiếu quyền này → AMG query AMP thành công nhưng trả empty data.
resource "aws_iam_role_policy" "amp_kms_read" {
  name = "${local.name_prefix}-amg-amp-kms-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAMPKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.amp_kms_key_arn
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
#
# BUG FIX: seconds_to_live = 0 is INVALID — AWS API rejects it.
# Valid range is 1 - 2592000 seconds (max 30 days). Token is
# rotated automatically every 25 days (before expiry) via
# time_rotating + replace_triggered_by, so the Terraform Provider
# never authenticates with a stale/expired token.

resource "aws_grafana_workspace_service_account" "terraform" {
  name         = "terraform-automation"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.this.id
}

resource "time_rotating" "grafana_token" {
  rotation_days = 25
}

resource "aws_grafana_workspace_service_account_token" "terraform" {
  name               = "terraform-token"
  # ⚠️ .id trả về composite "workspace-id/sa-id" → fail pattern ^[a-zA-Z0-9]+$
  # Phải dùng .service_account_id (chỉ phần numeric ID).
  service_account_id = aws_grafana_workspace_service_account.terraform.service_account_id
  seconds_to_live    = 2592000 # 30 days — AWS maximum allowed value
  workspace_id       = aws_grafana_workspace.this.id

  lifecycle {
    replace_triggered_by = [time_rotating.grafana_token]
  }
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

resource "aws_ssm_parameter" "service_account_token" {
  name   = "/${var.project_name}/${var.environment}/observability/amg_service_account_token"
  type   = "SecureString"
  value  = aws_grafana_workspace_service_account_token.terraform.key
  key_id = aws_kms_key.amg.arn # CMK riêng (kms.tf) — không dùng alias/aws/ssm mặc định
  tags   = local.tags

  lifecycle {
    # Token rotate mỗi 25 ngày qua time_rotating (xem resource
    # aws_grafana_workspace_service_account_token ở trên) → resource
    # đó bị replace → replace_triggered_by ở đây đảm bảo SSM
    # parameter cũng bị destroy + recreate TRONG CÙNG 1 apply, tránh
    # trường hợp lab-grafana pipeline đọc phải token cũ (stale) do
    # SSM value không tự đồng bộ với token mới.
    replace_triggered_by = [aws_grafana_workspace_service_account_token.terraform]
  }
}
