#--------------------------------------------------------------
# CLOUDWATCH ALARMS — ECS Resource Health (payment-service)
#
# A.2.T1 note: Container Insights đã được enable sẵn trong
#   modules/compute/ecs-cluster/main.tf (containerInsights = "enabled")
#   via control-plane/lab/main.tf (enable_container_insights = true).
#   KHÔNG cần thay đổi gì thêm.
#
# 3 alarms theo mục đích khác nhau:
#
#   Alarm 1 — MemoryUtilization > 85%  (LEADING indicator)
#     Namespace: AWS/ECS (built-in, luôn có)
#     Cảnh báo TRƯỚC khi OOM xảy ra. Khi alarm này fire mà không có
#     ai investigate, Alarm 3 (RunningTaskCount) sẽ fire tiếp theo.
#
#   Alarm 2 — CPUUtilization > 80% sustained  (AWARENESS)
#     Namespace: AWS/ECS (built-in)
#     Ghi nhận workload pattern bất thường. Không phải outage nhưng
#     là dấu hiệu cần right-sizing hoặc có traffic spike.
#
#   Alarm 3 — RunningTaskCount < 1  (LAGGING indicator)
#     Namespace: ECS/ContainerInsights (cần Container Insights enabled)
#     Service đang degraded — task chết hoàn toàn. treat_missing_data =
#     breaching vì không có metric = service đã chết hẳn.
#
# Tất cả fire vào SNS warning (Alarm 1 & 2) hoặc critical (Alarm 3).
# Lambda telegram-notifier nhận và format thành Telegram message.
#
# Sau khi apply, verify bằng:
#   aws cloudwatch describe-alarms --alarm-names \
#     obs-lab-payment-service-memory-high \
#     obs-lab-payment-service-cpu-high \
#     obs-lab-payment-service-running-task-low \
#     --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'
#
# Stress test (A.2.T3) — dùng ECS Exec sau khi alarms ở state OK:
#   CLUSTER=obs-cluster
#   SERVICE=payment-service
#   TASK=$(aws ecs list-tasks --cluster $CLUSTER \
#            --service-name $SERVICE \
#            --query 'taskArns[0]' --output text)
#   aws ecs execute-command --cluster $CLUSTER --task $TASK \
#     --container payment-service --interactive --command "/bin/sh"
#   # Trong container shell:
#   #   apt-get update -qq && apt-get install -y -qq stress-ng
#   #   stress-ng --vm 1 --vm-bytes 400M --timeout 180s
#--------------------------------------------------------------

locals {
  monitored_service = "payment-service"
  # ecs_cluster_name is already defined in eventbridge-ecs.tf
  # (module.ecs_cluster.cluster_name → "obs-cluster")
  # Re-referencing here via the same module output is safe — same locals block.
}

#--------------------------------------------------------------
# Alarm 1 — Memory > 85% (LEADING: predicts OOM kill)
#--------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.monitored_service}-memory-high"
  alarm_description = "MemoryUtilization > 85% — investigate before OOM kill (Experiment 3B leading indicator)"

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"
  # evaluation_periods × period = 2 × 60s = 2-min sustained breach before firing.
  # Avoids false alarms from transient GC spikes.
  period             = 60
  evaluation_periods = 2
  threshold          = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # missing datapoint = task starting/stopping, not a problem

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  ok_actions    = [module.alerting.sns_warning_arn] # notify when recovered (incident closed)

  tags = {
    Module      = "alarms-ecs"
    Severity    = "warning"
    Service     = local.monitored_service
    Type        = "leading"
    Environment = var.environment
    Project     = var.project_name
  }
}

#--------------------------------------------------------------
# Alarm 2 — CPU > 80% sustained (AWARENESS: workload anomaly)
#--------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.monitored_service}-cpu-high"
  alarm_description = "CPUUtilization > 80% for 5min — check for traffic spike or runaway process"

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  # 5 periods × 60s = 5-min sustained. CPU can burst briefly; 5-min is
  # the production-standard threshold for "something is actually wrong".
  period             = 60
  evaluation_periods = 5
  threshold          = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  # No ok_actions for CPU — informational only, not incident-grade.

  tags = {
    Module      = "alarms-ecs"
    Severity    = "warning"
    Service     = local.monitored_service
    Type        = "awareness"
    Environment = var.environment
    Project     = var.project_name
  }
}

#--------------------------------------------------------------
# Alarm 3 — RunningTaskCount < 1 (LAGGING: service is down)
#--------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_running_task_low" {
  alarm_name        = "${var.project_name}-${var.environment}-${local.monitored_service}-running-task-low"
  alarm_description = "RunningTaskCount = 0 — payment-service has no running tasks (outage)"

  # IMPORTANT: Different namespace from Alarm 1 & 2.
  # ECS/ContainerInsights is only populated when Container Insights is enabled
  # (enable_container_insights = true in ecs-cluster module → already done).
  namespace   = "ECS/ContainerInsights"
  metric_name = "RunningTaskCount"
  statistic   = "Average"
  period             = 60
  evaluation_periods = 2
  threshold          = 1
  comparison_operator = "LessThanThreshold"

  # treat_missing_data = "breaching" here is INTENTIONAL and different from Alarm 1/2.
  # If the metric stream stops (Container Insights lost, service totally gone),
  # we WANT the alarm to fire — silence = problem for this type of alarm.
  treat_missing_data = "breaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_critical_arn] # critical — service is down
  ok_actions    = [module.alerting.sns_critical_arn] # notify when task recovers

  tags = {
    Module      = "alarms-ecs"
    Severity    = "critical"
    Service     = local.monitored_service
    Type        = "lagging"
    Environment = var.environment
    Project     = var.project_name
  }
}
