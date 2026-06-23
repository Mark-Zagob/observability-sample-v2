#--------------------------------------------------------------
# CONTROL PLANE - LAB ENVIRONMENT
# Chỉ chứa "The Canvas" (VPC, IAM) và "The Engines" (RDS, ECR, ECS Cluster)
# TUYỆT ĐỐI KHÔNG chứa ECS Task Definition / ECS Service
#--------------------------------------------------------------

# 1. Network
module "network" {
  source             = "../../modules/network"
  project_name       = var.project_name
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
  
  enable_flow_logs                  = var.enable_flow_logs
  flow_logs_retention_days          = 30
  flow_logs_cloudwatch_traffic_type = "REJECT"
  enable_flow_logs_s3               = false

  common_tags = { Module = "network" }
}

# 2. VPC Endpoints
module "vpc_endpoints" {
  source       = "../../modules/vpc-endpoints"
  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr_block
  
  route_table_ids = concat(
    [module.network.public_route_table_id],
    values(module.network.private_route_table_ids),
    [module.network.data_route_table_id]
  )
  
  enable_interface_endpoints = var.enable_interface_endpoints
  private_subnet_ids         = module.network.private_subnet_ids
  common_tags                = { Module = "vpc-endpoints" }
}

# 3. Security (IAM Roles, SGs)
module "security" {
  source         = "../../modules/security"
  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.vpc_cidr_block
  app_ports      = var.app_ports
  
  enable_bastion    = var.enable_bastion
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  generate_ssh_key  = var.generate_ssh_key
  
  common_tags = { Module = "security" }
}

# 4. Database (RDS + KMS + Secrets Manager + SSM)
module "database" {
  source = "../../modules/database"
  project_name = var.project_name
  environment  = var.environment

  vpc_id                 = module.network.vpc_id
  data_subnet_ids        = module.network.data_subnet_ids
  data_security_group_id = module.security.data_security_group_id

  # RDS Configs
  instance_class             = var.db_instance_class
  db_name                    = var.db_name
  allocated_storage          = var.db_allocated_storage
  max_allocated_storage      = var.db_max_allocated_storage
  multi_az                   = var.db_multi_az
  backup_retention_period    = var.db_backup_retention_period
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  auto_minor_version_upgrade = var.db_auto_minor_version_upgrade
  apply_immediately          = var.db_apply_immediately
  
  enhanced_monitoring_interval = var.db_enhanced_monitoring_interval
  enable_cloudwatch_alarms     = var.db_enable_cloudwatch_alarms

  common_tags = { Module = "database", Backup = "true" }
}

# 5. ECR
module "ecr" {
  source             = "../../modules/ecr"
  project_name       = var.project_name
  repository_names   = var.ecr_repository_names
  image_tag_mutability = "MUTABLE"
  scan_on_push       = true
  common_tags        = { Module = "ecr" }
}

# 6. ECS Cluster (The Engine)
module "ecs_cluster" {
  source       = "../../modules/compute/ecs-cluster"
  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  namespace_name = "ecommerce.local"
  enable_container_insights = true
  common_tags  = { Module = "ecs-cluster" }
}

# 7. ACM & ALB (Optional - Giữ lại để sau này API Gateway / Web UI dùng)
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

module "acm" {
  source      = "../../modules/acm"
  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.main.zone_id
  common_tags = { Module = "acm" }
}

module "loadbalancer" {
  source                = "../../modules/loadbalancer"
  project_name          = var.project_name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  acm_certificate_arn   = module.acm.certificate_arn
  services              = var.alb_services # Map rỗng nếu chưa có service nào
  enable_deletion_protection = false
  common_tags           = { Module = "loadbalancer" }
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = module.loadbalancer.alb_dns_name
    zone_id                = module.loadbalancer.alb_zone_id
    evaluate_target_health = true
  }
}