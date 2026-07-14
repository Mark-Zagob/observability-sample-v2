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
  alias       = "${local.name_prefix}-amp"
  kms_key_arn = aws_kms_key.amp.arn
  tags        = local.tags
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
# 3. IAM — ADOT RemoteWrite (standalone policy, least privilege)
#--------------------------------------------------------------
# NOTE: Module KHÔNG tự attach policy vào ECS Task Role — role đó
# thuộc sở hữu module `security`, không phải module này. Attach
# được thực hiện ở caller (control-plane) qua
# aws_iam_role_policy_attachment, tránh cross-module mutation của
# 1 resource không thuộc sở hữu (anti-pattern: 2 modules cùng ghi
# vào 1 role → race condition / orphan policy khi destroy lệch thứ tự).
#
# Chỉ cấp aps:RemoteWrite — ADOT sidecar chỉ PUSH metrics, không query.
# Quyền query (GetSeries/GetLabels/GetMetricMetadata) thuộc về AMG's
# IAM role (modules/observability/amg), không phải ECS Task Role.

resource "aws_iam_policy" "ecs_task_remote_write" {
  name        = "${local.name_prefix}-amp-remote-write"
  description = "Least-privilege policy for ADOT sidecar RemoteWrite into AMP workspace ${local.name_prefix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAMPRemoteWrite"
        Effect   = "Allow"
        Action   = ["aps:RemoteWrite"]
        Resource = [aws_prometheus_workspace.this.arn]
      }
    ]
  })

  tags = local.tags
}

#--------------------------------------------------------------
# 4. CloudWatch Alarm — Cardinality Bomb Detection
#--------------------------------------------------------------
# Bảo vệ chi phí: nếu ActiveSeries vượt threshold → alarm.
# Nguyên nhân thường gặp: UUID label injection (Chaos Drill 9).

resource "aws_cloudwatch_metric_alarm" "cardinality_bomb" {
  alarm_name        = "${local.name_prefix}-amp-cardinality-bomb"
  alarm_description = "AMP ActiveSeries exceeded ${var.active_series_threshold}. Check for high-cardinality labels."
  namespace         = "AWS/Prometheus"
  metric_name       = "ActiveSeries"
  # Maximum thay vì Average — cardinality bomb là spike đột ngột (VD: UUID
  # label injection). Average trên period dài sẽ "làm mượt" và che mất spike.
  statistic           = "Maximum"
  period              = 300 # 5 phút — phát hiện nhanh hơn nhiều so với 1h cũ
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.active_series_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_critical_arn]
  ok_actions          = [var.sns_critical_arn] # notify khi resolved (đã fix cardinality)

  dimensions = {
    WorkspaceId = aws_prometheus_workspace.this.id
  }

  tags = merge(local.tags, {
    Severity = "critical"
    Type     = "finops"
  })
}
