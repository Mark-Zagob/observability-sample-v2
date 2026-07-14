output "sns_critical_arn" {
  value       = aws_sns_topic.critical.arn
  description = "ARN of the critical-severity SNS topic. Subscribe CloudWatch Alarms and EventBridge rules that indicate outages here."
}

output "sns_warning_arn" {
  value       = aws_sns_topic.warning.arn
  description = "ARN of the warning-severity SNS topic. Subscribe alarms for leading indicators (memory high, task anomalies) here."
}

output "lambda_arn" {
  value       = aws_lambda_function.telegram.arn
  description = "ARN of the Telegram notifier Lambda. Useful for direct invocation during smoke testing."
}

output "lambda_function_name" {
  value       = aws_lambda_function.telegram.function_name
  description = "Name of the Telegram notifier Lambda (for CLI invoke commands in the plan)."
}
