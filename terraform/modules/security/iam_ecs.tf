#--------------------------------------------------------------
# IAM — ECS Roles (Task Execution + Task)
#--------------------------------------------------------------
# Two separate roles following AWS best practice:
#
#   Task Execution Role:
#     WHO:  ECS Agent (not your app)
#     WHAT: Pull images from ECR, write logs to CloudWatch,
#           read secrets from SSM/SecretsManager
#     WHY:  Infra-level permissions for container lifecycle
#
#   Task Role:
#     WHO:  Your application code
#     WHAT: Call S3, SQS, DynamoDB — whatever the app needs
#     WHY:  App-level permissions, least-privilege per service
#
# Reference: AWS Well-Architected SEC03-BP06, SEC03-BP09
#--------------------------------------------------------------

# Data source for current partition and region
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
}


########################################################################
# ECS Task Execution Role
########################################################################
# Used by ECS Agent to:
# - Pull container images from ECR
# - Push logs to CloudWatch Logs
# - Read secrets from SSM Parameter Store / Secrets Manager
########################################################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTaskExecution"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*"
          }
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ecs-task-execution"
  })
}

# Attach managed policy (ECR pull + CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional: allow creating log groups (ECS auto-creates them)
resource "aws_iam_role_policy" "ecs_task_execution_logs" {
  name = "${var.project_name}-ecs-exec-logs"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCreateLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.project_name}*"
      }
    ]
  })
}

# Additional: read secrets from SSM / Secrets Manager (for DB passwords, API keys)
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-exec-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadSecrets"
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${var.project_name}/*",
          "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}/*"
        ]
      },
      {
        Sid    = "AllowDecryptSecrets"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        # When kms_key_arn is provided, restrict to that specific key.
        # Otherwise, fall back to wildcard scoped by kms:ViaService condition.
        Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}


########################################################################
# ECS Task Role
########################################################################
# Used by your application code inside the container.
# Start with minimal permissions — add more as services are needed.
########################################################################

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTask"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*"
          }
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ecs-task"
  })
}

# Base permissions: CloudWatch metrics + X-Ray traces
resource "aws_iam_role_policy" "ecs_task_base" {
  name = "${var.project_name}-ecs-task-base"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.project_name
          }
        }
      },
      {
        # X-Ray API does NOT support resource-level permissions.
        # Resource: "*" is required per AWS docs:
        # https://docs.aws.amazon.com/xray/latest/devguide/security_iam_id-based-policy-examples.html
        Sid    = "AllowXRayTraces"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowECSExec"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}
