variable "project_name" {
  type        = string
  description = "Project prefix used for resource naming (e.g. 'obs')."
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. 'lab', 'dev', 'prod')."
}

variable "telegram_secret_arn" {
  type        = string
  description = "Full ARN of the Secrets Manager secret holding {bot_token, chat_id}. Created manually via CLI — NOT managed by this module."
}

variable "telegram_secret_name" {
  type        = string
  description = "Name (path) of the Secrets Manager secret, passed as env var to Lambda (e.g. '/obs/lab/alerting/telegram')."
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Tags to attach to all resources in this module."
}
