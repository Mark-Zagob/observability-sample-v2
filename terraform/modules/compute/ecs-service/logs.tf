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
