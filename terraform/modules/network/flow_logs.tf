#--------------------------------------------------------------
# VPC Flow Logs → CloudWatch (Encrypted at Rest)
#--------------------------------------------------------------
locals {
  flow_logs = var.enable_flow_logs ? { "vpc" = aws_vpc.this.id } : {}
}

resource "aws_flow_log" "this" {
  for_each = local.flow_logs

  vpc_id          = each.value
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs[each.key].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[each.key].arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${each.key}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  for_each = local.flow_logs

  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = aws_kms_key.flow_logs[each.key].arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-flow-logs"
  })
}

#--------------------------------------------------------------
# KMS Key — Encrypt Flow Logs at Rest
#--------------------------------------------------------------
# Why: VPC Flow Logs contain sensitive network metadata (source/
# destination IPs, ports, protocols). CIS AWS Benchmark 3.x and
# AWS Well-Architected Framework require encryption at rest for
# all log data. Without KMS, logs are encrypted with default
# AWS-managed key which cannot be audited or rotated by the user.
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "flow_logs" {
  for_each = local.flow_logs

  description             = "KMS key for VPC Flow Logs encryption - ${var.project_name}"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow root account full access (required for key management)
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow CloudWatch Logs service to use this key
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/flow-logs/${var.project_name}"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-flow-logs-kms"
  })
}

resource "aws_kms_alias" "flow_logs" {
  for_each = local.flow_logs

  name          = "alias/${var.project_name}-flow-logs"
  target_key_id = aws_kms_key.flow_logs[each.key].key_id
}

#--------------------------------------------------------------
# IAM Role for Flow Logs
#--------------------------------------------------------------
resource "aws_iam_role" "flow_logs" {
  for_each = local.flow_logs

  name = "${var.project_name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  for_each = local.flow_logs

  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.flow_logs[each.key].arn,
          "${aws_cloudwatch_log_group.flow_logs[each.key].arn}:*"
        ]
      },
      {
        Sid    = "AllowKMSForFlowLogs"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = [
          aws_kms_key.flow_logs[each.key].arn
        ]
      }
    ]
  })
}
