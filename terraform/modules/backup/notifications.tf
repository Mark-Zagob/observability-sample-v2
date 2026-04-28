#--------------------------------------------------------------
# Backup Module — Notifications & Monitoring
#--------------------------------------------------------------
# Two notification channels:
#   1. SNS Topic → email → human notification
#   2. CloudWatch Alarm → detect backup job failures
#
# AWS Backup emits vault events to SNS:
#   BACKUP_JOB_COMPLETED, BACKUP_JOB_FAILED,
#   COPY_JOB_COMPLETED, COPY_JOB_FAILED,
#   RESTORE_JOB_COMPLETED, RESTORE_JOB_FAILED
#--------------------------------------------------------------

########################################################################
# SNS Topic for Backup Notifications
########################################################################

resource "aws_sns_topic" "backup" {
  name              = "${local.identifier}-notifications"
  kms_master_key_id = aws_kms_key.backup.id

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-notifications"
    Component = "backup"
  })
}

# SNS Topic Policy — allow AWS Backup service to publish
resource "aws_sns_topic_policy" "backup" {
  arn = aws_sns_topic.backup.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBackupServicePublish"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.backup.arn
      }
    ]
  })
}

# Email subscription (optional)
resource "aws_sns_topic_subscription" "backup_email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.backup.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

########################################################################
# Vault Notifications — backup/copy/restore events
########################################################################

resource "aws_backup_vault_notifications" "primary" {
  backup_vault_name = aws_backup_vault.primary.name
  sns_topic_arn     = aws_sns_topic.backup.arn

  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "COPY_JOB_FAILED",
    "RESTORE_JOB_FAILED",
    "BACKUP_JOB_COMPLETED",
    "COPY_JOB_SUCCESSFUL",
  ]
}

########################################################################
# CloudWatch Alarms — Backup Job Failures
########################################################################
# AWS Backup publishes metrics to CloudWatch:
#   NumberOfBackupJobsFailed
#   NumberOfCopyJobsFailed
#
# Alarm fires if any backup job fails in a 24-hour period.
# This catches silent failures that email notifications might miss
# (e.g., email filtered, mailbox full).
########################################################################

resource "aws_cloudwatch_metric_alarm" "backup_job_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.identifier}-backup-job-failed"
  alarm_description   = "AWS Backup job failed. Check AWS Backup console for details."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 86400 # 24 hours
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.backup.arn]

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-backup-failed-alarm"
    Component = "backup"
  })
}

resource "aws_cloudwatch_metric_alarm" "copy_job_failed" {
  count = var.enable_cloudwatch_alarms && var.enable_cross_region_copy ? 1 : 0

  alarm_name          = "${local.identifier}-copy-job-failed"
  alarm_description   = "AWS Backup cross-region copy failed. DR region may have stale data."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfCopyJobsFailed"
  namespace           = "AWS/Backup"
  period              = 86400
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.backup.arn]

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-copy-failed-alarm"
    Component = "backup"
    Purpose   = "disaster-recovery"
  })
}
