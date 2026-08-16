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
data "aws_ssm_parameter" "db_app_secret_arn" {
  name = "/obs/lab/database/app-secret-arn"
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

  # 🌟 FIX BOMB #1: Tăng thời gian chờ graceful shutdown
  stop_timeout = 60

  # 🌟 BẬT OBSERVABILITY BRIDGE với FinOps sampling
  enable_adot_sidecar  = true
  amp_endpoint         = data.aws_ssm_parameter.amp_endpoint.value
  traces_sampling_rate = 100  # Phase 1.5: lấy 100% traces để debug. Phase 4: giảm xuống 10.


  # Environment Variables
  environment = {
    SERVICE_NAME                = var.service_name
    PORT                        = tostring(var.container_port)
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
    PAYMENT_SERVICE_URL         = "http://payment-service.ecommerce.local:5002"
    DB_HOST                     = data.aws_ssm_parameter.db_host.value
    DB_PORT                     = data.aws_ssm_parameter.db_port.value
    DB_NAME                     = data.aws_ssm_parameter.db_name.value
    # Phase 1: Redis/Kafka not deployed yet → disable to avoid 62s retry blocks
    # Phase 2: Remove these lines when ElastiCache + MSK are deployed
    ENABLE_REDIS                = "false"
    ENABLE_KAFKA                = "false"
  }

  # Secrets (From SSM → Secrets Manager ARN)
  # 🔐 DML-only app_user secret (NOT master secret)
  secrets = {
    DB_SECRET = data.aws_ssm_parameter.db_app_secret_arn.value
  }

  common_tags = {
    Module  = "ecs-service"
    Service = var.service_name
    Plane   = "Data"
  }
}

#--------------------------------------------------------------
# MIGRATION GATE — Block deploy if migration not SUCCESS
#--------------------------------------------------------------
# Terraform check block (1.5+): warns/errors if migration
# hasn't completed before Data Plane deploy.
# SSM parameter written by bootstrap-migration local-exec.
#--------------------------------------------------------------
data "aws_ssm_parameter" "migration_status" {
  name = "/obs/lab/migration/status"
}

check "migration_gate" {
  assert {
    condition = data.aws_ssm_parameter.migration_status.value == "SUCCESS"

    # nonsensitive() AN TOÀN: giá trị là enum trạng thái (SUCCESS/FAILED) do
    # migration script tự ghi — KHÔNG phải secret. Provider đánh dấu mọi
    # SSM data source value là sensitive bất kể type thực tế.
    # Error message phải actionable: on-call đọc xong biết ngay bước tiếp theo.
    error_message = "🛑 BLOCKED: Migration status = '${nonsensitive(data.aws_ssm_parameter.migration_status.value)}' (expected: SUCCESS). Remediate: cd terraform/control-plane/lab && terraform apply -replace='module.bootstrap_migration.null_resource.run_migration' — chi tiết: docs/ADR-019_migration_orchestration.md"
  }
}
