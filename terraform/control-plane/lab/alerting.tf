#--------------------------------------------------------------
# ALERTING — SNS Topics + Lambda Telegram bridge
#
# Prerequisites (phải làm thủ công trước khi apply):
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
