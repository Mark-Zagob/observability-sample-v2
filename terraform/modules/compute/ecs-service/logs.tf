#--------------------------------------------------------------
# ECS Service Module — CloudWatch Log Groups
#--------------------------------------------------------------

resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${var.project_name}/${var.service_name}"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name    = "/ecs/${var.project_name}/${var.service_name}"
    Service = var.service_name
  })
}

resource "aws_cloudwatch_log_group" "otel" {
  count = var.enable_adot_sidecar ? 1 : 0

  name              = "/ecs/${var.project_name}/${var.service_name}/otel"
  retention_in_days = 14

  tags = merge(var.common_tags, {
    Name    = "/ecs/${var.project_name}/${var.service_name}/otel"
    Service = var.service_name
  })
}

#--------------------------------------------------------------
# CloudWatch Metric Filter — Application Error Rate
#--------------------------------------------------------------
# Scans this service's log group for JSON logs with "level": "ERROR".
# Creates custom metric in CloudWatch: {project}/ApplicationMetrics/AppErrorCount.
# The corresponding ALARM lives in control-plane/observability.tf
# (alarms don't need the log group to exist).
#--------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  count = var.enable_app_error_metric ? 1 : 0

  name           = "${var.project_name}-${var.service_name}-app-errors"
  log_group_name = aws_cloudwatch_log_group.service.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name      = "AppErrorCount"
    namespace = "${var.project_name}/ApplicationMetrics"
    value     = "1"
    dimensions = {
      ServiceName = "$.name"
    }
  }
}
