#--------------------------------------------------------------
# Shared Environment - Main
# Wire modules vào đây, mỗi lần thêm module mới sẽ thêm 1 block
#--------------------------------------------------------------

#--------------------------------------------------------------
# Module 1: Network (VPC, Subnets, NAT, Flow Logs)
#--------------------------------------------------------------
module "network" {
  source = "../../modules/network"
  #source = "git::ssh://git@github.com/Mark-Zagob/observability-sample-v2.git//terraform/modules/network?ref=network/v1.0.1"
  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_cidr     = var.vpc_cidr

  # Subnet CIDRs: tự tính bằng cidrsubnet() từ vpc_cidr
  # → 10.0.0.0/16 → public: .1-.3, private: .11-.13, data: .21-.23

  # NAT Gateway: true = 1 NAT (save $2/day), false = 3 NAT (HA)
  single_nat_gateway = var.single_nat_gateway

  # VPC Flow Logs: ghi network traffic vào CloudWatch
  enable_flow_logs         = var.enable_flow_logs
  flow_logs_retention_days = 30 # Minimum per logging compliance policy

  common_tags = {
    Module = "network"
  }
}

#--------------------------------------------------------------
# Module 2: VPC Endpoints (S3, DynamoDB Gateway + Interface)
# Tách riêng khỏi network module theo Single Responsibility Principle.
# Gateway endpoints (S3, DynamoDB) = FREE — should always be enabled.
# Interface endpoints = optional, ~$7.2/month per endpoint per AZ.
#--------------------------------------------------------------
module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr_block

  # Gateway Endpoints cần tất cả route tables
  route_table_ids = concat(
    [module.network.public_route_table_id],
    values(module.network.private_route_table_ids),
    values(module.network.mgmt_route_table_ids),
    [module.network.data_route_table_id]
  )

  # Interface Endpoints (costs ~$7.2/month per endpoint per AZ)
  enable_interface_endpoints = var.enable_interface_endpoints
  private_subnet_ids         = module.network.private_subnet_ids

  common_tags = {
    Module = "vpc-endpoints"
  }
}

#--------------------------------------------------------------
# Module 3: Security (SGs, IAM Roles, Key Pair)
#--------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.vpc_cidr_block

  # Application
  app_port = var.app_port

  # Bastion
  enable_bastion    = var.enable_bastion
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  generate_ssh_key  = var.generate_ssh_key

  # Port maps: sử dụng defaults từ module
  # Override nếu cần: db_ports = { postgres = 5432 }

  common_tags = {
    Module = "security"
  }
}

#--------------------------------------------------------------
# Module 4: Database (RDS PostgreSQL + Secrets + SSM + Monitoring)
#--------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name = var.project_name
  environment  = var.environment

  # From network module
  vpc_id          = module.network.vpc_id
  data_subnet_ids = module.network.data_subnet_ids

  # From security module
  data_security_group_id = module.security.data_security_group_id

  # RDS configuration (override via terraform.tfvars per env)
  instance_class        = var.db_instance_class
  db_name               = var.db_name
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  # Production toggles
  multi_az                   = var.db_multi_az
  backup_retention_period    = var.db_backup_retention_period
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  auto_minor_version_upgrade = var.db_auto_minor_version_upgrade
  apply_immediately          = var.db_apply_immediately

  # Monitoring
  enhanced_monitoring_interval = var.db_enhanced_monitoring_interval
  enable_cloudwatch_alarms     = var.db_enable_cloudwatch_alarms

  common_tags = {
    Module = "database"
  }
}

#--------------------------------------------------------------
# Module 5: Cache (ElastiCache Redis) — sẽ thêm sau
#--------------------------------------------------------------
# module "cache" {
#   source = "../../modules/cache"
#   ...
# }

#--------------------------------------------------------------
# Module 6: Streaming (MSK Kafka) — sẽ thêm sau
#--------------------------------------------------------------
# module "streaming" {
#   source = "../../modules/streaming"
#   ...
# }
