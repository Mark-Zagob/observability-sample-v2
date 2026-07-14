terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

#--------------------------------------------------------------
# 1. SNS TOPICS — 2 severity levels
#    critical → outage / deployment failed / task count = 0
#    warning  → resource spike / task stopped abnormally
#--------------------------------------------------------------

resource "aws_sns_topic" "critical" {
  name = "${var.project_name}-${var.environment}-alerts-critical"
  tags = merge(var.common_tags, { Severity = "critical" })
}

resource "aws_sns_topic" "warning" {
  name = "${var.project_name}-${var.environment}-alerts-warning"
  tags = merge(var.common_tags, { Severity = "warning" })
}

# Allow EventBridge and CloudWatch (Alarms) to publish into these topics.
# Using for_each to avoid code duplication, with a conditional ARN reference.
data "aws_iam_policy_document" "sns_publish" {
  for_each = toset(["critical", "warning"])

  statement {
    sid     = "AllowAWSServicesToPublish"
    actions = ["sns:Publish"]
    resources = [
      each.key == "critical" ? aws_sns_topic.critical.arn : aws_sns_topic.warning.arn
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "critical" {
  arn    = aws_sns_topic.critical.arn
  policy = data.aws_iam_policy_document.sns_publish["critical"].json
}

resource "aws_sns_topic_policy" "warning" {
  arn    = aws_sns_topic.warning.arn
  policy = data.aws_iam_policy_document.sns_publish["warning"].json
}

#--------------------------------------------------------------
# 2. LAMBDA — Telegram Notifier
#    Zip the Python source file at plan/apply time.
#--------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/telegram_notifier.py"
  output_path = "${path.module}/lambda/telegram_notifier.zip"
}

# --- IAM Role for Lambda ---

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-${var.environment}-telegram-notifier"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}

# Basic execution: write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege: only read the specific Telegram secret
data "aws_iam_policy_document" "lambda_secret_read" {
  statement {
    sid       = "ReadTelegramSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.telegram_secret_arn]
  }
}

resource "aws_iam_role_policy" "lambda_secret_read" {
  name   = "read-telegram-secret"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secret_read.json
}

# --- Lambda Function ---

resource "aws_lambda_function" "telegram" {
  function_name    = "${var.project_name}-${var.environment}-telegram-notifier"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "telegram_notifier.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TELEGRAM_SECRET_ID = var.telegram_secret_name
    }
  }

  tags = var.common_tags
}

#--------------------------------------------------------------
# 3. SNS → Lambda wiring
#    Permission + Subscription for both topics.
#--------------------------------------------------------------

locals {
  sns_topics = {
    critical = aws_sns_topic.critical.arn
    warning  = aws_sns_topic.warning.arn
  }
}

# Allow SNS to invoke the Lambda function
resource "aws_lambda_permission" "allow_sns_invoke" {
  for_each = local.sns_topics

  statement_id  = "AllowSNSInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.telegram.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value
}

# Subscribe Lambda to both topics
resource "aws_sns_topic_subscription" "telegram_critical" {
  topic_arn = aws_sns_topic.critical.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.telegram.arn
}

resource "aws_sns_topic_subscription" "telegram_warning" {
  topic_arn = aws_sns_topic.warning.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.telegram.arn
}
