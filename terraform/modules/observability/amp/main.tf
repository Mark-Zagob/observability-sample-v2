#--------------------------------------------------------------
# Main — observability/amp
#--------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(var.common_tags, {
    Module      = "observability-amp"
    Plane       = "Control"
    Environment = var.environment
    Project     = var.project_name
  })
}

#--------------------------------------------------------------
# 1. AMP Workspace
#--------------------------------------------------------------
resource "aws_prometheus_workspace" "this" {
  alias = "${local.name_prefix}-amp"
  tags  = local.tags
}

#--------------------------------------------------------------
# 2. SSM Parameters — Cross-plane discovery
#--------------------------------------------------------------
# Pattern: /{project}/{env}/observability/{key}
# Data Plane (ECS services) đọc AMP endpoint để configure ADOT sidecar.

resource "aws_ssm_parameter" "workspace_id" {
  name  = "/${var.project_name}/${var.environment}/observability/amp_workspace_id"
  type  = "String"
  value = aws_prometheus_workspace.this.id
  tags  = local.tags
}

resource "aws_ssm_parameter" "endpoint" {
  name  = "/${var.project_name}/${var.environment}/observability/amp_endpoint"
  type  = "String"
  value = aws_prometheus_workspace.this.prometheus_endpoint
  tags  = local.tags
}

#--------------------------------------------------------------
# 3. IAM — ADOT RemoteWrite (least privilege)
#--------------------------------------------------------------
# Gắn vào ECS Task Role → ADOT sidecar push metrics về AMP.
# Scoped chặt vào ARN của workspace này (không wildcard).

resource "aws_iam_role_policy" "ecs_task_remote_write" {
  name = "${local.name_prefix}-amp-remote-write"
  role = var.ecs_task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAMPRemoteWrite"
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = [aws_prometheus_workspace.this.arn]
      }
    ]
  })
}

#--------------------------------------------------------------
# 4. CloudWatch Alarm — Cardinality Bomb Detection
#--------------------------------------------------------------
# Bảo vệ chi phí: nếu ActiveSeries vượt threshold → alarm.
# Nguyên nhân thường gặp: UUID label injection (Chaos Drill 9).

resource "aws_cloudwatch_metric_alarm" "cardinality_bomb" {
  alarm_name          = "${local.name_prefix}-amp-cardinality-bomb"
  alarm_description   = "AMP ActiveSeries exceeded ${var.active_series_threshold}. Check for high-cardinality labels."
  namespace           = "AWS/Prometheus"
  metric_name         = "ActiveSeries"
  statistic           = "Average"
  period              = 3600 # 1 hour
  evaluation_periods  = 1
  threshold           = var.active_series_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_critical_arn]

  dimensions = {
    WorkspaceId = aws_prometheus_workspace.this.id
  }

  tags = merge(local.tags, {
    Severity = "critical"
    Type     = "finops"
  })
}
