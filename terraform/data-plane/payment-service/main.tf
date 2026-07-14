#--------------------------------------------------------------
# DATA PLANE — PAYMENT SERVICE
# Đọc "Service Catalog" từ SSM Parameter Store
#--------------------------------------------------------------

# 1. Đọc Network Metadata từ SSM
data "aws_ssm_parameter" "private_subnets" {
  name = "/obs/lab/network/private_subnets"
}

data "aws_ssm_parameter" "app_sg_id" {
  name = "/obs/lab/security/app_sg_id"
}

# 2. Đọc IAM Roles từ SSM
data "aws_ssm_parameter" "task_execution_role" {
  name = "/obs/lab/iam/task_execution_role_arn"
}

data "aws_ssm_parameter" "task_role" {
  name = "/obs/lab/iam/task_role_arn"
}

# 3. Đọc Compute Metadata từ SSM
data "aws_ssm_parameter" "ecs_cluster_id" {
  name = "/obs/lab/compute/ecs_cluster_id"
}

data "aws_ssm_parameter" "cloudmap_namespace" {
  name = "/obs/lab/compute/cloudmap_namespace_id"
}

# 4. Đọc ECR URL từ SSM (Dynamic theo service name)
data "aws_ssm_parameter" "ecr_url" {
  name = "/obs/lab/ecr/${var.service_name}"
}

# 6. Đọc Observability Metadata từ SSM
data "aws_ssm_parameter" "amp_endpoint" {
  name = "/obs/lab/observability/amp_endpoint"
}

#--------------------------------------------------------------
# LOCALS: Construct Image URL
#--------------------------------------------------------------
locals {
  # Tách subnets từ StringList "subnet-1,subnet-2" thành List
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnets.value)
  
  # Construct Image URL: ECR URL + Image Tag từ variables
  payment_image = format("%s:%s", data.aws_ssm_parameter.ecr_url.value, var.image_tag)
}

#--------------------------------------------------------------
# DEPLOY ECS SERVICE
#--------------------------------------------------------------
module "payment_service" {
  source = "../../modules/compute/ecs-service"
  
  project_name   = var.project_name
  service_name   = var.service_name
  cluster_id     = data.aws_ssm_parameter.ecs_cluster_id.value
  image          = local.payment_image
  container_port = var.container_port
  aws_region     = "ap-southeast-2"

  # Network & Security (From SSM)
  subnets         = local.private_subnet_ids
  security_groups = [data.aws_ssm_parameter.app_sg_id.value]

  # IAM (From SSM)
  execution_role_arn = data.aws_ssm_parameter.task_execution_role.value
  task_role_arn      = data.aws_ssm_parameter.task_role.value

  # Service Discovery
  enable_load_balancer     = false
  enable_service_discovery = true
  namespace_id             = data.aws_ssm_parameter.cloudmap_namespace.value

  # Sizing
  cpu    = var.cpu
  memory = var.memory

  # 🌟 FIX BOMB #1: Tăng thời gian chờ graceful shutdown
  stop_timeout = 60

  # 🌟 BẬT OBSERVABILITY BRIDGE với FinOps sampling
  enable_adot_sidecar  = true
  amp_endpoint         = data.aws_ssm_parameter.amp_endpoint.value
  traces_sampling_rate = 100  # Phase 1.5: lấy 100% traces để debug. Phase 4: giảm xuống 10.

  # Environment Variables
  environment = {
    SERVICE_NAME                  = var.service_name
    PORT                          = tostring(var.container_port)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    # Phase 1: Redis not deployed yet → disable idempotency
    # Phase 2: Remove this line when ElastiCache is deployed
    ENABLE_REDIS                  = "false"
  }

  # Secrets: none — payment-service uses Redis only, no PostgreSQL

  common_tags = { 
    Module  = "ecs-service"
    Service = var.service_name
    Plane   = "Data"
  }
}