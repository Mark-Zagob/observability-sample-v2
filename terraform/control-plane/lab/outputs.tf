#--------------------------------------------------------------
# CONTROL PLANE OUTPUTS (THE CONTRACT)
# Data Plane sẽ đọc các outputs này qua `terraform_remote_state`
#--------------------------------------------------------------

# 1. Network Contract
output "vpc_id" { value = module.network.vpc_id }
output "private_subnet_ids" { value = module.network.private_subnet_ids }

# 2. Security Contract (IAM & SG)
output "app_security_group_id" { value = module.security.application_security_group_id }
output "ecs_task_execution_role_arn" { value = module.security.ecs_task_execution_role_arn }
output "ecs_task_role_arn" { value = module.security.ecs_task_role_arn }
output "kms_rds_key_arn" {
  description = "KMS Key ARN dùng để mã hóa RDS & Secrets. Data Plane cần quyền Decrypt."
  value       = module.database.kms_key_arn
}

# 3. Database Contract
output "db_secret_arn" { value = module.database.db_secret_arn }
output "ssm_db_prefix" {
  description = "Prefix để Data Plane tự lên SSM đọc DB_HOST, DB_PORT..."
  value       = module.database.ssm_parameter_prefix
}

# 4. Compute Contract
output "ecs_cluster_id" { value = module.ecs_cluster.cluster_id }
output "cloudmap_namespace_id" { value = module.ecs_cluster.namespace_id }

# 5. ECR Contract
output "ecr_repository_urls" { value = module.ecr.repository_urls }

# 6. ALB Contract
output "alb_target_group_arns" { value = module.loadbalancer.target_group_arns }

# 7. Observability Contract
output "amp_prometheus_endpoint" {
  description = "AMP remote write / query endpoint URL"
  value       = module.amp.prometheus_endpoint
}

output "amg_workspace_endpoint" {
  description = "AMG workspace URL — mở trong browser để access Grafana"
  value       = module.amg.workspace_endpoint
}

output "amg_workspace_id" {
  description = "AMG workspace ID — dùng cho API/CLI operations"
  value       = module.amg.workspace_id
}