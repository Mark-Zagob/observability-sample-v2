#--------------------------------------------------------------
# Logging Module — KMS Encryption
#--------------------------------------------------------------
# Dedicated CMK for flow log S3 bucket encryption.
# Separate from VPC Flow Logs CloudWatch KMS key (in network module)
# and backup vault KMS key — defense-in-depth:
# compromising one key doesn't expose other log stores.
#
# Reference: AWS Well-Architected SEC08-BP01, CIS AWS 2.1.1
#--------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  identifier = "${var.project_name}-${var.environment}-logging"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

resource "aws_kms_key" "flow_logs_s3" {
  description             = "CMK for flow logs S3 bucket encryption — ${local.identifier}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow root account full access (required for key management)
      {
        Sid    = "AllowRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow VPC Flow Logs delivery service to encrypt log files
      {
        Sid    = "AllowFlowLogsDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-flow-logs-s3-kms"
    Component = "logging"
  })
}

resource "aws_kms_alias" "flow_logs_s3" {
  name          = "alias/${local.identifier}-flow-logs-s3"
  target_key_id = aws_kms_key.flow_logs_s3.key_id
}
