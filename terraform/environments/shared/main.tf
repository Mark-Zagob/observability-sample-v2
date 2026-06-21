#--------------------------------------------------------------
# Shared Environment - Main
# Wire modules vào đây, mỗi lần thêm module mới sẽ thêm 1 block
#--------------------------------------------------------------
# Image source: Toggle giữa ECR và Docker Hub
# Chỉ dùng 1 trong 2 — comment/uncomment để chuyển đổi

# Option A: ECR (production — image đã push lên ECR)
locals {
  service_images = {
    for name in var.ecr_repository_names : name =>
    "${module.ecr.repository_urls[name]}:${lookup(var.image_tags, name, "latest")}"
  }
}

# Option B: Docker Hub (thay <dockerhub-user> bằng username thật)
# locals {
#   service_images = {
#     for name in var.ecr_repository_names : name =>
#     "<dockerhub-user>/${name}:${lookup(var.image_tags, name, "latest")}"
#   }
# }

# Module 1: Logging (S3 + Athena for centralized log storage)
# Must be deployed before network — network needs bucket ARN.
# Separate lifecycle: destroying VPC does NOT destroy log archive.
#--------------------------------------------------------------
# module "logging-flow-logs" {
#   source = "../../modules/logging-flow-logs"

#   project_name = var.project_name
#   environment  = var.environment

#   # Lifecycle: Standard (0-90d) → Glacier (90-365d) → Delete
#   flow_logs_glacier_transition_days = 90
#   flow_logs_expiration_days         = 365

#   common_tags = {
#     Module = "logging"
#   }
# }

#--------------------------------------------------------------
# Module 2: Network (VPC, Subnets, NAT, Flow Logs)
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

  # VPC Flow Logs: dual-destination (CloudWatch + S3)
  enable_flow_logs                  = var.enable_flow_logs
  flow_logs_retention_days          = 30                                  # Minimum per logging compliance policy
  flow_logs_cloudwatch_traffic_type = "REJECT"                            # Cost: only security events to CloudWatch
  enable_flow_logs_s3               = false                                # Enable S3 destination (static, plan-time)
  #flow_logs_s3_bucket_arn           = module.logging-flow-logs.flow_logs_bucket_arn # ALL traffic to S3

  common_tags = {
    Module = "network"
  }
  # additional_subnet_tags = {
  #   public = {
  #     "kubernetes.io/cluster/my-eks-cluster" = "shared"
  #   }
  #   private = {
  #     "kubernetes.io/cluster/my-eks-cluster" = "shared"
  #   }
  # }
}

#--------------------------------------------------------------
# Module 3: VPC Endpoints (S3, DynamoDB Gateway + Interface)
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
# Module 4: Security (SGs, IAM Roles, Key Pair)
#--------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.vpc_cidr_block

  # Application — multi-port for 6 microservices
  app_ports = var.app_ports

  # Bastion
  enable_bastion    = var.enable_bastion
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  generate_ssh_key  = var.generate_ssh_key

  # KMS key for ECS secret decryption (wired from database module)
  # Uncomment after database module is deployed:
  # kms_key_arn = module.database.kms_key_arn

  # Port maps: sử dụng defaults từ module
  # Override nếu cần: db_ports = { postgres = 5432 }

  common_tags = {
    Module = "security"
  }
}

#--------------------------------------------------------------
# Module 5: Database (RDS PostgreSQL + Secrets + SSM + Monitoring)
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
    Backup = "true" # ← AWS Backup auto-discovers this resource
  }
}

#--------------------------------------------------------------
# Module 6: Backup (AWS Backup + Cross-Region Copy)
# DISABLED — Re-enable khi có workload chạy thật
# Iron Rule: No Infra without Workload
# Codebase giữ nguyên tại modules/backup/
#--------------------------------------------------------------
# module "backup" {
#   source = "../../modules/backup"
#
#   providers = {
#     aws    = aws
#     aws.dr = aws.dr
#   }
#
#   project_name = var.project_name
#   environment  = var.environment
#
#   # Vault configuration
#   vault_lock_mode = var.backup_vault_lock_mode
#
#   # Daily backup: 35 days retention
#   daily_schedule       = "cron(0 3 * * ? *)"
#   daily_retention_days = var.backup_daily_retention_days
#
#   # Monthly backup: 365 days retention, cold storage after 30d
#   enable_monthly_plan             = var.backup_enable_monthly_plan
#   monthly_retention_days          = var.backup_monthly_retention_days
#   monthly_cold_storage_after_days = 30
#
#   # Cross-region copy (DR Tier 1)
#   enable_cross_region_copy         = var.backup_enable_cross_region_copy
#   cross_region_copy_retention_days = var.backup_cross_region_retention_days
#
#   # Notifications
#   notification_email       = var.backup_notification_email
#   enable_cloudwatch_alarms = var.backup_enable_cloudwatch_alarms
#
#   # Compliance reporting (SOC2/HIPAA)
#   enable_backup_reports = true
#
#   common_tags = {
#     Module = "backup"
#   }
# }

#--------------------------------------------------------------
# Module 7: ECR (Container Repositories)
#--------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  repository_names = var.ecr_repository_names

  image_tag_mutability = "MUTABLE" # Lab — switch to IMMUTABLE for production
  scan_on_push         = true
  max_tagged_images    = 10
  untagged_expiry_days = 7

  common_tags = {
    Module = "ecr"
  }
}

#--------------------------------------------------------------
# Module 8: ACM (TLS Certificate + DNS Validation)
#--------------------------------------------------------------
module "acm" {
  source = "../../modules/acm"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.main.zone_id

  common_tags = {
    Module = "acm"
  }
}

# Data source: existing Route 53 Hosted Zone
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

#--------------------------------------------------------------
# Module 9: Loadbalancer (ALB + HTTPS + Target Groups)
#--------------------------------------------------------------
module "loadbalancer" {
  source = "../../modules/loadbalancer"

  project_name          = var.project_name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  acm_certificate_arn   = module.acm.certificate_arn

  # Services exposed via ALB (add as you onboard)
  services = var.alb_services

  enable_deletion_protection = false # Lab — true for production

  common_tags = {
    Module = "loadbalancer"
  }
}

# Route 53 A record: domain → ALB
# (Placed here to avoid circular dependency between acm ↔ loadbalancer)
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

#--------------------------------------------------------------
# Module 10: ECS Cluster + Cloud Map
#--------------------------------------------------------------
module "ecs_cluster" {
  source = "../../modules/compute/ecs-cluster"

  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  namespace_name = "ecommerce.local"

  enable_container_insights = true

  common_tags = {
    Module = "ecs-cluster"
  }
}

#--------------------------------------------------------------
# Module 11+: ECS Services (one module call per microservice)
# Onboard step-by-step — uncomment as you progress through Steps
#--------------------------------------------------------------

# Step 1: Payment Service (stateless, no ALB, Cloud Map only)
module "payment_service" {
  source = "../../modules/compute/ecs-service"

  project_name   = var.project_name
  service_name   = "payment-service"
  cluster_id     = module.ecs_cluster.cluster_id
  image          = local.service_images["payment-service"]
  container_port = 5002
  aws_region     = var.aws_region

  # Networking
  subnets         = module.network.private_subnet_ids
  security_groups = [module.security.application_security_group_id]

  # IAM
  execution_role_arn = module.security.ecs_task_execution_role_arn
  task_role_arn      = module.security.ecs_task_role_arn

  # No ALB — internal service only (Cloud Map discovery)
  enable_load_balancer = false

  # Cloud Map: payment-service.ecommerce.local
  enable_service_discovery = true
  namespace_id             = module.ecs_cluster.namespace_id

  # Task sizing (lab — minimal)
  cpu    = 256
  memory = 512

  # App config
  environment = {
    SERVICE_NAME = "payment-service"
    PORT         = "5002"
    DB_HOST      = module.database.rds_address
    DB_PORT      = tostring(module.database.rds_port)
    DB_NAME      = module.database.rds_db_name
    # 👇 FIX Q1: Trỏ OTel SDK về ADOT Sidecar (localhost của Fargate Task)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    
    # 👇 FIX BOM #1: Inject Redis URL (Dù chưa có Redis, inject vào để App fail-fast 
    # ở tầng connection, thay vì lỗi DNS undefined)
    REDIS_URL   
  }
  secrets = {
    DB_SECRET = module.database.db_secret_arn
  }

  common_tags = {
    Module = "ecs-service"
    Step   = "1"
  }
}

# Step 2: Order Service (uncomment when ready)
# module "order_service" {
#   source         = "../../modules/compute/ecs-service"
#   project_name   = var.project_name
#   service_name   = "order-service"
#   cluster_id     = module.ecs_cluster.cluster_id
#   image          = local.service_images["order-service"]
#   container_port = 5001
#   aws_region     = var.aws_region
#   subnets         = module.network.private_subnet_ids
#   security_groups = [module.security.application_security_group_id]
#   execution_role_arn = module.security.ecs_task_execution_role_arn
#   task_role_arn      = module.security.ecs_task_role_arn
#   enable_load_balancer = false
#   enable_service_discovery = true
#   namespace_id             = module.ecs_cluster.namespace_id
#   cpu    = 256
#   memory = 512
#   environment = {
#     SERVICE_NAME        = "order-service"
#     PORT                = "5001"
#     DB_HOST             = module.database.rds_address
#     DB_PORT             = tostring(module.database.rds_port)
#     DB_NAME             = module.database.rds_db_name
#     PAYMENT_SERVICE_URL = "http://payment-service.ecommerce.local:5002"
#   }
#   secrets = { DB_SECRET = module.database.db_secret_arn }
#   common_tags = { Module = "ecs-service", Step = "2" }
# }

# Step 3: API Gateway (uncomment when ready)
# module "api_gateway" {
#   source         = "../../modules/compute/ecs-service"
#   project_name   = var.project_name
#   service_name   = "api-gateway"
#   cluster_id     = module.ecs_cluster.cluster_id
#   image          = local.service_images["api-gateway"]
#   container_port = 5000
#   aws_region     = var.aws_region
#   subnets         = module.network.private_subnet_ids
#   security_groups = [module.security.application_security_group_id]
#   execution_role_arn = module.security.ecs_task_execution_role_arn
#   task_role_arn      = module.security.ecs_task_role_arn
#   enable_load_balancer = true
#   target_group_arn     = module.loadbalancer.target_group_arns["api-gateway"]
#   enable_service_discovery = true
#   namespace_id             = module.ecs_cluster.namespace_id
#   cpu    = 256
#   memory = 512
#   environment = {
#     SERVICE_NAME      = "api-gateway"
#     PORT              = "5000"
#     ORDER_SERVICE_URL = "http://order-service.ecommerce.local:5001"
#   }
#   common_tags = { Module = "ecs-service", Step = "3" }
# }

# Step 4: Web UI (uncomment when ready)
# module "web_ui" {
#   source         = "../../modules/compute/ecs-service"
#   project_name   = var.project_name
#   service_name   = "web-ui"
#   cluster_id     = module.ecs_cluster.cluster_id
#   image          = local.service_images["web-ui"]
#   container_port = 8080
#   aws_region     = var.aws_region
#   subnets         = module.network.private_subnet_ids
#   security_groups = [module.security.application_security_group_id]
#   execution_role_arn = module.security.ecs_task_execution_role_arn
#   task_role_arn      = module.security.ecs_task_role_arn
#   enable_load_balancer = true
#   target_group_arn     = module.loadbalancer.target_group_arns["web-ui"]
#   enable_service_discovery = true
#   namespace_id             = module.ecs_cluster.namespace_id
#   cpu    = 256
#   memory = 512
#   environment = {
#     SERVICE_NAME    = "web-ui"
#     PORT            = "8080"
#     API_GATEWAY_URL = "http://api-gateway.ecommerce.local:5000"
#   }
#   common_tags = { Module = "ecs-service", Step = "4" }
# }

# Step 5-6: Notification/Inventory Workers (Kafka consumers — future)
# Cần MSK/Redis modules trước

#--------------------------------------------------------------
# Module: Cache (ElastiCache Redis) — sẽ thêm sau
#--------------------------------------------------------------
# module "cache" {
#   source = "../../modules/cache"
#   ...
# }

#--------------------------------------------------------------
# Module: Streaming (MSK Kafka) — sẽ thêm sau
#--------------------------------------------------------------
# module "streaming" {
#   source = "../../modules/streaming"
#   ...
# }
