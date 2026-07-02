#--------------------------------------------------------------
# DATA PLANE — ORDER SERVICE
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

# 5. Đọc Database config từ SSM
data "aws_ssm_parameter" "db_secret_arn" {
  name = "/obs/lab/database/secret-arn"
}

data "aws_ssm_parameter" "db_host" {
  name = "/obs/lab/database/host"
}

data "aws_ssm_parameter" "db_port" {
  name = "/obs/lab/database/port"
}

data "aws_ssm_parameter" "db_name" {
  name = "/obs/lab/database/name"
}

#--------------------------------------------------------------
# LOCALS: Construct Image URL
#--------------------------------------------------------------
locals {
  # Tách subnets từ StringList "subnet-1,subnet-2" thành List
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnets.value)

  # Construct Image URL: ECR URL + Image Tag từ variables
  order_image = format("%s:%s", data.aws_ssm_parameter.ecr_url.value, var.image_tag)
}

#--------------------------------------------------------------
# DEPLOY ECS SERVICE
#--------------------------------------------------------------
module "order_service" {
  source = "../../modules/compute/ecs-service"

  project_name   = var.project_name
  service_name   = var.service_name
  cluster_id     = data.aws_ssm_parameter.ecs_cluster_id.value
  image          = local.order_image
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

  # Environment Variables
  environment = {
    SERVICE_NAME                = var.service_name
    PORT                        = tostring(var.container_port)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    PAYMENT_SERVICE_URL         = "http://payment-service.ecommerce.local:5002"
    DB_HOST                     = data.aws_ssm_parameter.db_host.value
    DB_PORT                     = data.aws_ssm_parameter.db_port.value
    DB_NAME                     = data.aws_ssm_parameter.db_name.value
  }

  # Secrets (From SSM → Secrets Manager ARN)
  secrets = {
    DB_SECRET = data.aws_ssm_parameter.db_secret_arn.value
  }

  common_tags = {
    Module  = "ecs-service"
    Service = var.service_name
    Plane   = "Data"
  }
}
