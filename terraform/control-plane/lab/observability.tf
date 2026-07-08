#--------------------------------------------------------------
# OBSERVABILITY — Alerting Pipeline (SNS + Lambda + EventBridge + CloudWatch Alarms)
#
# Flow:
#   ECS Events → EventBridge Rules ──┐
#                                     ├→ SNS Topics → Lambda → Telegram
#   ECS Metrics → CloudWatch Alarms ─┘
#
# Sections:
#   1. Alerting Module (SNS topics + Lambda Telegram bridge)
#   2. EventBridge Rules (ECS deployment & task failure events)
#   3. CloudWatch Alarms (Memory, CPU, RunningTaskCount)
#
# Prerequisites (1 lần):
#   aws secretsmanager create-secret \
#     --name /obs/lab/alerting/telegram \
#     --secret-string '{"bot_token":"<TOKEN>","chat_id":"<CHAT_ID>"}' \
#     --region ap-southeast-2
#
# Verify sau khi apply:
#   aws lambda invoke \
#     --function-name obs-lab-telegram-notifier \
#     --payload '{"Records":[{"Sns":{"TopicArn":"arn:aws:sns:ap-southeast-2:730335245469:obs-lab-alerts-critical","Message":"{\"AlarmName\":\"smoke-test\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"manual smoke test\",\"Region\":\"ap-southeast-2\",\"AWSAccountId\":\"730335245469\"}"}}]}' \
#     --cli-binary-format raw-in-base64-out /tmp/lambda_out.json && cat /tmp/lambda_out.json
#--------------------------------------------------------------

# ============================================================
# 1. ALERTING MODULE — SNS Topics + Lambda Telegram bridge
# ============================================================

# Read the Telegram secret that was pre-created via CLI (not managed by Terraform).
# Terraform only reads the ARN — plaintext never touches state.
data "aws_secretsmanager_secret" "telegram" {
  name = "/obs/lab/alerting/telegram"
}

module "alerting" {
  source = "../../modules/alerting"

  project_name         = var.project_name
  environment          = var.environment
  telegram_secret_arn  = data.aws_secretsmanager_secret.telegram.arn
  telegram_secret_name = data.aws_secretsmanager_secret.telegram.name

  common_tags = {
    Module = "alerting"
    Plane  = "Control"
  }
}

# ============================================================
# 2. EVENTBRIDGE RULES — ECS Failure Events
# ============================================================
#
# Rule 1 (critical): ECS Deployment State Change → SERVICE_DEPLOYMENT_FAILED
#   Bắt được: Experiment 1 (IAM Blackhole), Experiment 3A (Bad Image),
#             Experiment 3B (OOM gây Circuit Breaker trip).
#
# Rule 2 (warning): ECS Task State Change → STOPPED abnormally
#   Bắt được: ExitCode 137 (OOM Kill), ExitCode 1 (App crash / bad env var),
#             CannotPullContainerError (Birth failure).
#   Filter bằng stopCode:
#     - TaskFailedToStart       = Birth failure
#     - EssentialContainerExited = Runtime failure
#   Loại trừ: UserInitiated và ServiceSchedulerInitiated (normal stop).

locals {
  ecs_cluster_arn  = module.ecs_cluster.cluster_arn
  ecs_cluster_name = module.ecs_cluster.cluster_name

  # Thêm service mới vào list này khi onboard
  monitored_services = toset(["payment-service", "order-service"])
}

# --- Rule 1: Deployment circuit-breaker failure (CRITICAL) ---

resource "aws_cloudwatch_event_rule" "ecs_deployment_failed" {
  name        = "${var.project_name}-${var.environment}-ecs-deployment-failed"
  description = "ECS deployment circuit-breaker tripped → SERVICE_DEPLOYMENT_FAILED. Covers IAM Blackhole, Bad Image, OOM (Experiments 1 & 3)."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    detail = {
      eventType  = ["SERVICE_DEPLOYMENT_FAILED"]
      clusterArn = [local.ecs_cluster_arn]
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
  description = "ECS task stopped with stopCode TaskFailedToStart or EssentialContainerExited. Maps to ExitCode null (Birth failure) or 137/1 (Runtime failure)."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      lastStatus = ["STOPPED"]
      stopCode   = ["EssentialContainerExited", "TaskFailedToStart"]
      clusterArn = [local.ecs_cluster_arn]
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
#
# Container Insights đã enable trong modules/compute/ecs-cluster/main.tf.
#
#   Alarm 1 — MemoryUtilization > 85%  (LEADING indicator)
#   Alarm 2 — CPUUtilization > 80%     (AWARENESS)
#   Alarm 3 — RunningTaskCount < 1     (LAGGING indicator)
#
#   Dùng for_each để tạo alarm cho mọi service trong monitored_services.
#
# Verify:
#   aws cloudwatch describe-alarms --alarm-names \
#     obs-lab-payment-service-memory-high \
#     obs-lab-order-service-memory-high \
#     obs-lab-payment-service-cpu-high \
#     obs-lab-order-service-cpu-high \
#     obs-lab-payment-service-running-task-low \
#     obs-lab-order-service-running-task-low \
#     --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'

# --- Alarm 1: Memory > 85% (LEADING: predicts OOM kill) ---

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  for_each = local.monitored_services

  alarm_name        = "${var.project_name}-${var.environment}-${each.key}-memory-high"
  alarm_description = "${each.key} MemoryUtilization > 85% — investigate before OOM kill"

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"
  # evaluation_periods × period = 2 × 60s = 2-min sustained breach before firing.
  # Avoids false alarms from transient GC spikes.
  period              = 60
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # missing datapoint = task starting/stopping, not a problem

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = each.key
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  ok_actions    = [module.alerting.sns_warning_arn] # notify when recovered (incident closed)

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Service     = each.key
    Type        = "leading"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Alarm 2: CPU > 80% sustained (AWARENESS: workload anomaly) ---

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  for_each = local.monitored_services

  alarm_name        = "${var.project_name}-${var.environment}-${each.key}-cpu-high"
  alarm_description = "${each.key} CPUUtilization > 80% for 5min — check for traffic spike or runaway process"

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  # 5 periods × 60s = 5-min sustained. CPU can burst briefly; 5-min is
  # the production-standard threshold for "something is actually wrong".
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = each.key
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  # No ok_actions for CPU — informational only, not incident-grade.

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Service     = each.key
    Type        = "awareness"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Alarm 3: RunningTaskCount < 1 (LAGGING: service is down) ---

resource "aws_cloudwatch_metric_alarm" "ecs_running_task_low" {
  for_each = local.monitored_services

  alarm_name        = "${var.project_name}-${var.environment}-${each.key}-running-task-low"
  alarm_description = "${each.key} RunningTaskCount = 0 — no running tasks (outage)"

  # IMPORTANT: Different namespace from Alarm 1 & 2.
  # ECS/ContainerInsights is only populated when Container Insights is enabled.
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  # treat_missing_data = "breaching" here is INTENTIONAL and different from Alarm 1/2.
  # If the metric stream stops, we WANT the alarm to fire — silence = problem.
  treat_missing_data = "breaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = each.key
  }

  alarm_actions = [module.alerting.sns_critical_arn] # critical — service is down
  ok_actions    = [module.alerting.sns_critical_arn] # notify when task recovers

  tags = {
    Module      = "observability"
    Severity    = "critical"
    Service     = each.key
    Type        = "lagging"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ============================================================
# 4. CLOUDWATCH ALARM — Application Error Rate
# ============================================================
#
#   Bridges the gap: Infra Monitoring → Application Monitoring (APM).
#
#   Alarms 1-3 above catch INFRA failures (CPU, RAM, Task count).
#   This alarm catches APP failures:
#     - DB connection errors
#     - Payment service timeout (order → payment)
#     - Unhandled exceptions
#     - Business logic errors (e.g., insufficient inventory)
#
#   Architecture:
#     - METRIC FILTER lives in ecs-service module (data-plane) — co-located with log group
#     - ALARM lives here (control-plane) — doesn't need log group to exist
#     - Alarm will be INSUFFICIENT_DATA until data-plane deploys and generates metrics
#
#   App logs are JSON structured (pythonjsonlogger):
#     {"timestamp": "...", "level": "ERROR", "name": "order-service", "message": "..."}
#
# Verify:
#   aws cloudwatch describe-alarms --alarm-names \
#     obs-lab-payment-service-app-error-rate \
#     obs-lab-order-service-app-error-rate \
#     --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'

resource "aws_cloudwatch_metric_alarm" "app_error_rate" {
  for_each = local.monitored_services

  alarm_name        = "${var.project_name}-${var.environment}-${each.key}-app-error-rate"
  alarm_description = "${each.key} application errors detected in logs — check for DB failures, timeouts, or unhandled exceptions"

  namespace   = "${var.project_name}/ApplicationMetrics"
  metric_name = "AppErrorCount"
  statistic   = "Sum"
  period      = 300 # 5 minutes
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  # Missing data = no errors = healthy
  treat_missing_data = "notBreaching"

  dimensions = {
    ServiceName = each.key
  }

  alarm_actions = [module.alerting.sns_warning_arn] # warning — app error, not outage
  ok_actions    = [module.alerting.sns_warning_arn] # notify when errors stop

  tags = {
    Module      = "observability"
    Severity    = "warning"
    Service     = each.key
    Type        = "application"
    Environment = var.environment
    Project     = var.project_name
  }
}

#============================================================
# PHASE 1.5: OBSERVABILITY BRIDGE — AMP & ADOT IAM
#============================================================

# 1. Tạo AMP Workspace (Nơi lưu trữ Metrics)
resource "aws_prometheus_workspace" "main" {
  alias = "${var.project_name}-${var.environment}-amp"
  
  tags = {
    Module      = "observability"
    Plane       = "Control"
    Environment = var.environment
    Project     = var.project_name
  }
}

# 2. Export AMP Endpoint & ID ra SSM để Data Plane đọc
resource "aws_ssm_parameter" "amp_workspace_id" {
  name  = "/${var.project_name}/${var.environment}/observability/amp_workspace_id"
  type  = "String"
  value = aws_prometheus_workspace.main.id
}

resource "aws_ssm_parameter" "amp_endpoint" {
  name  = "/${var.project_name}/${var.environment}/observability/amp_endpoint"
  type  = "String"
  value = aws_prometheus_workspace.main.prometheus_endpoint
}

# 3. 🛡️ IAM LEAST PRIVILEGE (Trả lời Câu hỏi 4)
# Gắn quyền aps:RemoteWrite trực tiếp vào Task Role (App-level)
# VÀ scope chặt chẽ vào ĐÚNG ARN của workspace này (không dùng wildcard "*")
resource "aws_iam_role_policy" "ecs_task_amp_remote_write" {
  name = "${var.project_name}-ecs-task-amp-remote-write"
  role = module.security.ecs_task_role_name # Đọc từ module security
  
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
        # 🌟 BẠN HỎI: "Làm sao để scope chặt?" -> Đây là câu trả lời!
        Resource = [aws_prometheus_workspace.main.arn]
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "amp_cardinality_bomb" {
  alarm_name          = "${var.project_name}-amp-cardinality-bomb"
  namespace           = "AWS/Usage"
  metric_name         = "ActiveSeries"
  statistic           = "Average"
  period              = 3600 # 1 hour
  evaluation_periods  = 1
  threshold           = 10000 # Hard limit cho Lab (Production có thể là 100,000)
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.alerting.sns_critical_arn]
}