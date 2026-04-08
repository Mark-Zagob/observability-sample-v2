#--------------------------------------------------------------
# Security Module - Outputs
#--------------------------------------------------------------

# Security Group IDs
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

output "observability_security_group_id" {
  description = "Security Group ID for observability stack"
  value       = aws_security_group.observability.id
}

output "bastion_security_group_id" {
  description = "Security Group ID for bastion host"
  value       = aws_security_group.bastion.id
}

output "efs_security_group_id" {
  description = "Security Group ID for EFS"
  value       = aws_security_group.efs.id
}

# IAM Roles
output "ecs_task_execution_role_arn" {
  description = "ARN of ECS Task Execution Role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of ECS Task Role"
  value       = aws_iam_role.ecs_task.arn
}

output "bastion_instance_profile_name" {
  description = "Name of Bastion IAM Instance Profile"
  value       = aws_iam_instance_profile.bastion.name
}

output "bastion_role_arn" {
  description = "ARN of Bastion IAM Role"
  value       = aws_iam_role.bastion.arn
}

# Key Pair
output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.main.key_name
}
