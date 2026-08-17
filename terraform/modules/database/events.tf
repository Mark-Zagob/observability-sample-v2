#--------------------------------------------------------------
# Database Module — RDS Event Subscription
#--------------------------------------------------------------
# Production pattern: Get notified on critical RDS events.
# Categories:
#   - availability: failover, restart, recovery
#   - configuration change: parameter group, SG changes
#   - maintenance: pending maintenance, patching
#   - failure: storage full, replication errors
#
# Events are published to SNS topic (same as alarm notifications).
# In production, this SNS topic triggers PagerDuty/Slack/email.
#--------------------------------------------------------------

resource "aws_db_event_subscription" "main" {
  count = var.alarm_sns_topic_arn != "" ? 1 : 0

  name      = "${local.identifier}-events"
  sns_topic = var.alarm_sns_topic_arn

  source_type = "db-instance"
  source_ids  = [aws_db_instance.postgres.identifier]

  # Subscribe to critical event categories
  event_categories = [
    "availability",
    "configuration change",
    "deletion",
    "failover",
    "failure",
    "maintenance",
    "notification",
    "recovery",
  ]

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-event-sub"
    Component = "database"
  })
}
