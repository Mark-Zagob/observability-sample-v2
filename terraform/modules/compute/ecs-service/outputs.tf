#--------------------------------------------------------------
# ECS Service Module — Outputs
#--------------------------------------------------------------

output "service_id" {
  description = "ECS Service ID"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Current task definition ARN"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family name (for CI/CD updates)"
  value       = aws_ecs_task_definition.this.family
}

output "discovery_service_arn" {
  description = "Cloud Map service ARN (empty if service discovery disabled)"
  value       = var.enable_service_discovery ? aws_service_discovery_service.this[0].arn : ""
}

output "log_group_name" {
  description = "CloudWatch Log Group name for the service"
  value       = aws_cloudwatch_log_group.service.name
}
