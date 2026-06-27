#--------------------------------------------------------------
# EVENTBRIDGE — ECS Failure Event Rules
#
# Rule 1 (critical): ECS Deployment State Change → SERVICE_DEPLOYMENT_FAILED
#   Bắt được: Experiment 1 (IAM Blackhole), Experiment 3A (Bad Image),
#             Experiment 3B (OOM gây Circuit Breaker trip).
#   Trigger: EventBridge fires khi deployment circuit breaker kích hoạt và
#            rollback bắt đầu — ngay cả khi Running task count vẫn = 1.
#
# Rule 2 (warning): ECS Task State Change → STOPPED abnormally
#   Bắt được: ExitCode 137 (OOM Kill), ExitCode 1 (App crash / bad env var),
#             CannotPullContainerError (Birth failure).
#   Filter bằng stopCode thay vì stoppedReason:
#     - TaskFailedToStart       = Birth failure (IAM, image pull, OOM tại start)
#     - EssentialContainerExited = Runtime failure (OOM kill, app crash)
#   Loại trừ: UserInitiated và ServiceSchedulerInitiated (normal stop).
#
# Diagram:
#   aws.ecs → EventBridge → SNS critical → Lambda → Telegram 🚨
#   aws.ecs → EventBridge → SNS warning  → Lambda → Telegram ⚠️
#--------------------------------------------------------------

# Extract cluster name from full ARN for scoping event patterns.
# cluster_arn format: arn:aws:ecs:<region>:<account>:cluster/<name>
locals {
  ecs_cluster_arn  = module.ecs_cluster.cluster_arn
  ecs_cluster_name = module.ecs_cluster.cluster_name
}

#--------------------------------------------------------------
# RULE 1 — Deployment circuit-breaker failure (CRITICAL)
#--------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "ecs_deployment_failed" {
  name        = "${var.project_name}-${var.environment}-ecs-deployment-failed"
  description = "ECS deployment circuit-breaker tripped → SERVICE_DEPLOYMENT_FAILED. Covers IAM Blackhole, Bad Image, OOM (Experiments 1 & 3)."

  # EventBridge ECS Deployment State Change event shape:
  # {
  #   "source": "aws.ecs",
  #   "detail-type": "ECS Deployment State Change",
  #   "detail": {
  #     "eventType": "SERVICE_DEPLOYMENT_FAILED",   ← primary field (AWS docs)
  #     "clusterArn": "arn:aws:ecs:.../cluster/<name>",
  #     "reason": "ECS deployment circuit breaker: ..."
  #   }
  # }
  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    detail = {
      eventType  = ["SERVICE_DEPLOYMENT_FAILED"]
      clusterArn = [local.ecs_cluster_arn]
    }
  })

  tags = {
    Module      = "eventbridge-ecs"
    Severity    = "critical"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "deployment_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_deployment_failed.name
  target_id = "to-sns-critical"
  arn       = module.alerting.sns_critical_arn
  # No input_transformer needed — Lambda formats the raw EventBridge JSON.
}

#--------------------------------------------------------------
# RULE 2 — Task stopped abnormally (WARNING)
#--------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "ecs_task_stopped_abnormal" {
  name        = "${var.project_name}-${var.environment}-ecs-task-stopped-abnormal"
  description = "ECS task stopped with stopCode TaskFailedToStart or EssentialContainerExited. Maps to ExitCode null (Birth failure) or 137/1 (Runtime failure)."

  # EventBridge ECS Task State Change event shape (relevant fields):
  # {
  #   "source": "aws.ecs",
  #   "detail-type": "ECS Task State Change",
  #   "detail": {
  #     "lastStatus": "STOPPED",
  #     "stopCode": "EssentialContainerExited" | "TaskFailedToStart"
  #                  | "UserInitiated" | "ServiceSchedulerInitiated",
  #     "stoppedReason": "Essential container in task exited" | ...
  #     "clusterArn": "arn:aws:ecs:.../cluster/<name>",
  #     "containers": [{ "exitCode": 137, "reason": "OOM..." }, ...]
  #   }
  # }
  #
  # stopCode semantics (why these two?):
  #   TaskFailedToStart       — container never started (IAM, image pull, OOM at init)
  #                             → ExitCode null  (Experiment 1, 3A)
  #   EssentialContainerExited — container ran then died (OOM kill, app crash)
  #                             → ExitCode 137 or 1  (Experiment 3B + Scenario C)
  #   UserInitiated           — EXCLUDE: manual `aws ecs stop-task` (not a failure)
  #   ServiceSchedulerInitiated — EXCLUDE: normal scale-in / rolling deploy
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
    Module      = "eventbridge-ecs"
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
