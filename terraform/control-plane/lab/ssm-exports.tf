#--------------------------------------------------------------
# CONTROL PLANE — SSM SERVICE CATALOG
# Nơi Control Plane "niêm yết" các metadata cho Data Plane đọc
# Convention: /{project}/{environment}/{domain}/{resource}
#--------------------------------------------------------------

# 1. NETWORK DOMAIN
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/${var.project_name}/${var.environment}/network/vpc_id"
  type  = "String"
  value = module.network.vpc_id

  tags = { Domain = "network", Consumer = "all-data-planes" }
}

resource "aws_ssm_parameter" "private_subnets" {
  name  = "/${var.project_name}/${var.environment}/network/private_subnets"
  type  = "StringList" # 🌟 Dùng StringList để lưu List
  value = join(",", module.network.private_subnet_ids)

  tags = { Domain = "network" }
}

# 2. SECURITY DOMAIN
resource "aws_ssm_parameter" "app_sg_id" {
  name  = "/${var.project_name}/${var.environment}/security/app_sg_id"
  type  = "String"
  value = module.security.application_security_group_id

  tags = { Domain = "security" }
}

resource "aws_ssm_parameter" "task_execution_role_arn" {
  name  = "/${var.project_name}/${var.environment}/iam/task_execution_role_arn"
  type  = "String"
  value = module.security.ecs_task_execution_role_arn

  tags = { Domain = "iam" }
}

resource "aws_ssm_parameter" "task_role_arn" {
  name  = "/${var.project_name}/${var.environment}/iam/task_role_arn"
  type  = "String"
  value = module.security.ecs_task_role_arn

  tags = { Domain = "iam" }
}

# 3. COMPUTE DOMAIN
resource "aws_ssm_parameter" "ecs_cluster_id" {
  name  = "/${var.project_name}/${var.environment}/compute/ecs_cluster_id"
  type  = "String"
  value = module.ecs_cluster.cluster_id

  tags = { Domain = "compute" }
}

resource "aws_ssm_parameter" "cloudmap_namespace_id" {
  name  = "/${var.project_name}/${var.environment}/compute/cloudmap_namespace_id"
  type  = "String"
  value = module.ecs_cluster.namespace_id

  tags = { Domain = "compute" }
}

# 4. ECR DOMAIN (Dùng for_each để dynamic hóa)
resource "aws_ssm_parameter" "ecr_urls" {
  for_each = module.ecr.repository_urls

  name  = "/${var.project_name}/${var.environment}/ecr/${each.key}"
  type  = "String"
  value = each.value

  tags = { Domain = "ecr", Service = each.key }
}

# 5. ALERTING DOMAIN
# SNS ARN được export để EventBridge rules và CloudWatch Alarms ở các file
# khác (eventbridge-ecs.tf, alarms-ecs.tf) có thể đọc qua SSM thay vì
# hard-depend vào module output — giúp sau này tách state nếu cần.
resource "aws_ssm_parameter" "sns_critical_arn" {
  name  = "/${var.project_name}/${var.environment}/alerting/sns_critical_arn"
  type  = "String"
  value = module.alerting.sns_critical_arn

  tags = { Domain = "alerting", Severity = "critical" }
}

resource "aws_ssm_parameter" "sns_warning_arn" {
  name  = "/${var.project_name}/${var.environment}/alerting/sns_warning_arn"
  type  = "String"
  value = module.alerting.sns_warning_arn

  tags = { Domain = "alerting", Severity = "warning" }
}

#--------------------------------------------------------------
# 📢 OUTPUT: Prefix để Data Plane xây dựng IAM Policy Wildcard
#--------------------------------------------------------------
output "ssm_catalog_prefix" {
  description = "Base prefix cho toàn bộ Service Catalog"
  value       = "/${var.project_name}/${var.environment}"
}