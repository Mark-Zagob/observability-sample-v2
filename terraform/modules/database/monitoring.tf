#--------------------------------------------------------------
# Database Module — Monitoring & Alerting
#--------------------------------------------------------------

#--------------------------------------------------------------
# CloudWatch Log Group for RDS PostgreSQL Logs
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "rds_postgres" {
  name              = "/aws/rds/instance/${local.identifier}/postgresql"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = aws_kms_key.rds.arn

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-pg-logs"
    Component = "database"
  })
}

#--------------------------------------------------------------
# Enhanced Monitoring IAM Role
# Required when monitoring_interval > 0
#--------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  name = "${local.identifier}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-monitoring-role"
    Component = "database"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.enhanced_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#--------------------------------------------------------------
# CloudWatch Alarms
#--------------------------------------------------------------

# Alarm: High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.identifier}-cpu-high"
  alarm_description   = "RDS CPU utilization > ${var.alarm_cpu_threshold}% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-cpu-alarm"
    Component = "database"
  })
}

# Alarm: Low Free Storage Space
resource "aws_cloudwatch_metric_alarm" "storage_low" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.identifier}-storage-low"
  alarm_description   = "RDS free storage < ${var.alarm_free_storage_threshold / 1000000000} GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_free_storage_threshold

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-storage-alarm"
    Component = "database"
  })
}

# Alarm: High Database Connections
resource "aws_cloudwatch_metric_alarm" "connections_high" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.identifier}-connections-high"
  alarm_description   = "RDS database connections > 80% of max"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold = var.alarm_connections_threshold

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-connections-alarm"
    Component = "database"
  })
}

#--------------------------------------------------------------
# Alarm: Secret Rotation Failure
# AWS auto-rotates the RDS managed secret every 7 days.
# This alarm fires if rotation FAILS (e.g., network issue,
# KMS key unavailable, insufficient IAM permissions).
#--------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "secret_rotation_failure" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.identifier}-secret-rotation-failed"
  alarm_description   = "RDS managed secret rotation has failed. Check CloudTrail for RotationFailed events."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RotationFailed"
  namespace           = "AWS/SecretsManager"
  period              = 86400 # 24 hours
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-rotation-failure-alarm"
    Component = "database"
    Purpose   = "rotation-monitoring"
  })
}

#--------------------------------------------------------------
# Alarm: Replica Lag (one per replica)
# Critical for detecting stale reads in production.
# PostgreSQL async replication: lag > 30s = data inconsistency risk.
#--------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  count = var.read_replica_count > 0 && var.enable_cloudwatch_alarms ? var.read_replica_count : 0

  alarm_name          = "${local.identifier}-replica-${count.index}-lag-high"
  alarm_description   = "Replica ${count.index} replication lag > 30 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 30
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.read_replica[count.index].identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-replica-${count.index}-lag-alarm"
    Component = "database"
  })
}
