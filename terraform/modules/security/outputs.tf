#--------------------------------------------------------------
# Security Module — Outputs
#--------------------------------------------------------------
# Outputs consumed by downstream modules:
#   - Data module   → data_security_group_id
#   - Compute module → alb_sg, app_sg, ecs_roles
#   - Bastion setup  → bastion_sg, instance_profile, key_pair
#--------------------------------------------------------------

#--------------------------------------------------------------
# Security Group IDs
#--------------------------------------------------------------

output "alb_security_group_id" {
  description = "Security Group ID for ALB"
  value       = aws_security_group.alb.id
}

output "application_security_group_id" {
  description = "Security Group ID for application containers"
  value       = aws_security_group.application.id
}

output "data_security_group_id" {
  description = "Security Group ID for data layer (RDS, Redis, MSK)"
  value       = aws_security_group.data.id
}

output "efs_security_group_id" {
  description = "Security Group ID for EFS mount targets"
  value       = aws_security_group.efs.id
}

output "observability_security_group_id" {
  description = "Security Group ID for observability stack"
  value       = aws_security_group.observability.id
}

output "bastion_security_group_id" {
  description = "Security Group ID for bastion host (empty string if disabled)"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : ""
}

#--------------------------------------------------------------
# Security Group IDs — Map (for_each-friendly)
#--------------------------------------------------------------

output "security_group_ids" {
  description = "Map of all security group IDs for bulk operations"
  value = {
    alb           = aws_security_group.alb.id
    application   = aws_security_group.application.id
    data          = aws_security_group.data.id
    efs           = aws_security_group.efs.id
    observability = aws_security_group.observability.id
    bastion       = var.enable_bastion ? aws_security_group.bastion[0].id : ""
  }
}

#--------------------------------------------------------------
# IAM Roles — ECS
#--------------------------------------------------------------

output "ecs_task_execution_role_arn" {
  description = "ARN of ECS Task Execution Role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of ECS Task Execution Role"
  value       = aws_iam_role.ecs_task_execution.name
}

output "ecs_task_role_arn" {
  description = "ARN of ECS Task Role (app-level permissions)"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  description = "Name of ECS Task Role"
  value       = aws_iam_role.ecs_task.name
}

#--------------------------------------------------------------
# IAM Roles — Bastion
#--------------------------------------------------------------

output "bastion_instance_profile_name" {
  description = "Name of Bastion IAM Instance Profile (empty string if disabled)"
  value       = var.enable_bastion ? aws_iam_instance_profile.bastion[0].name : ""
}

output "bastion_instance_profile_arn" {
  description = "ARN of Bastion IAM Instance Profile (empty string if disabled)"
  value       = var.enable_bastion ? aws_iam_instance_profile.bastion[0].arn : ""
}

output "bastion_role_arn" {
  description = "ARN of Bastion IAM Role (empty string if disabled)"
  value       = var.enable_bastion ? aws_iam_role.bastion[0].arn : ""
}

#--------------------------------------------------------------
# Key Pair
#--------------------------------------------------------------

output "key_pair_name" {
  description = "Name of the SSH key pair (empty string if disabled)"
  value       = local.key_pair_name
}
