#--------------------------------------------------------------
# Bootstrap Migration Module — Outputs
#--------------------------------------------------------------

output "task_definition_arn" {
  description = "ARN of the migration ECS task definition"
  value       = aws_ecs_task_definition.migration.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group for migration audit trail"
  value       = aws_cloudwatch_log_group.migration.name
}

output "migration_role_arn" {
  description = "IAM role ARN used by the migration task"
  value       = aws_iam_role.migration.arn
}
