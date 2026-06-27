#--------------------------------------------------------------
# OBSERVABILITY — Alerting Pipeline (SNS + Lambda + EventBridge + CloudWatch Alarms)
#
# All-in-one equivalent of control-plane/lab/observability.tf.
# Difference: shared/ wires directly via module outputs (same state),
# whereas CP/DP uses SSM Service Catalog for cross-state references.
#
# Flow:
#   ECS Events → EventBridge Rules ──┐
#                                     ├→ SNS Topics → Lambda → Telegram
#   ECS Metrics → CloudWatch Alarms ─┘
#
# Prerequisites (1 lần):
#   aws secretsmanager create-secret \
#     --name /obs/lab/alerting/telegram \
#     --secret-string '{"bot_token":"<TOKEN>","chat_id":"<CHAT_ID>"}' \
#     --region ap-southeast-2
#--------------------------------------------------------------

# ============================================================
# 1. ALERTING MODULE — SNS Topics + Lambda Telegram bridge
# ============================================================

data "aws_secretsmanager_secret" "telegram" {
  name = "/obs/${var.environment}/alerting/telegram"
}

module "alerting" {
  source = "../../modules/alerting"

  project_name         = var.project_name
  environment          = var.environment
  telegram_secret_arn  = data.aws_secretsmanager_secret.telegram.arn
  telegram_secret_name = data.aws_secretsmanager_secret.telegram.name

  common_tags = {
    Module = "alerting"
  }
}

# ============================================================
# 2. EVENTBRIDGE RULES — ECS Failure Events
# ============================================================

locals {
  obs_cluster_arn       = module.ecs_cluster.cluster_arn
  obs_cluster_name      = module.ecs_cluster.cluster_name
  obs_monitored_service = "payment-service"
}

# --- Rule 1: Deployment circuit-breaker failure (CRITICAL) ---

resource "aws_cloudwatch_event_rule" "ecs_deployment_failed" {
  name        = "${var.project_name}-${var.environment}-ecs-deployment-failed"
  description = "ECS deployment circuit-breaker tripped → SERVICE_DEPLOYMENT_FAILED."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    detail = {
      eventType  = ["SERVICE_DEPLOYMENT_FAILED"]
      clusterArn = [local.obs_cluster_arn]
    }
  })

  tags = {
    Module      = "observability"
    Severity    = "critical"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "deployment_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_deployment_failed.name
  target_id = "to-sns-critical"
  arn       = module.alerting.sns_critical_arn
}

# --- Rule 2: Task stopped abnormally (WARNING) ---

resource "aws_cloudwatch_event_rule" "ecs_task_stopped_abnormal" {
  name        = "${var.project_name}-${var.environment}-ecs-task-stopped-abnormal"
  description = "ECS task stopped with stopCode TaskFailedToStart or EssentialContainerExited."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      lastStatus = ["STOPPED"]
      stopCode   = ["EssentialContainerExited", "TaskFailedToStart"]
      clusterArn = [local.obs_cluster_arn]
    }
  })

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "task_stopped_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped_abnormal.name
  target_id = "to-sns-warning"
  arn       = module.alerting.sns_warning_arn
}

# ============================================================
# 3. CLOUDWATCH ALARMS — ECS Resource Health
# ============================================================

# --- Alarm 1: Memory > 85% (LEADING: predicts OOM kill) ---

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.obs_monitored_service}-memory-high"
  alarm_description = "MemoryUtilization > 85% — investigate before OOM kill"

  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.obs_cluster_name
    ServiceName = local.obs_monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  ok_actions    = [module.alerting.sns_warning_arn]

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Service     = local.obs_monitored_service
    Type        = "leading"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Alarm 2: CPU > 80% sustained (AWARENESS: workload anomaly) ---

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.obs_monitored_service}-cpu-high"
  alarm_description = "CPUUtilization > 80% for 5min — check for traffic spike or runaway process"

  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.obs_cluster_name
    ServiceName = local.obs_monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Service     = local.obs_monitored_service
    Type        = "awareness"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Alarm 3: RunningTaskCount < 1 (LAGGING: service is down) ---

resource "aws_cloudwatch_metric_alarm" "ecs_running_task_low" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.obs_monitored_service}-running-task-low"
  alarm_description = "RunningTaskCount = 0 — payment-service has no running tasks (outage)"

  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = local.obs_cluster_name
    ServiceName = local.obs_monitored_service
  }

  alarm_actions = [module.alerting.sns_critical_arn]
  ok_actions    = [module.alerting.sns_critical_arn]

  tags = {
    Module      = "observability"
    Severity    = "critical"
    Service     = local.obs_monitored_service
    Type        = "lagging"
    Environment = var.environment
    Project     = var.project_name
  }
}
