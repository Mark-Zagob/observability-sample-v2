#--------------------------------------------------------------
# ECS Service Module — Task Definition
#--------------------------------------------------------------
# Builds container definitions dynamically:
#   - App container (always)
#   - ADOT sidecar (when enable_adot_sidecar = true)
#
# Container communication within a task uses localhost.
# App → localhost:4317 (ADOT OTLP gRPC endpoint)
#--------------------------------------------------------------

locals {
  # --- App Container ---
  app_container = {
    name      = var.service_name
    image     = var.image
    essential = true

    # 🌟 FIX BOMB #1: Cấp cho App 60s để graceful shutdown
    # Khi ECS scale-in/deploy, nó gửi SIGTERM và chờ 60s trước khi SIGKILL.
    # Gunicorn (graceful_timeout=25s) sẽ flush xong request và tắt sạch sẽ trong 25s.
    # 35s còn lại là buffer an toàn cho OS/ECS Agent dọn dẹp.
    stopTimeout = var.stop_timeout
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [for k, v in var.environment : { name = k, value = v }]
    secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}${var.health_check_path}')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  # --- ADOT Sidecar Container (Enhanced for Phase 1.5) ---
  adot_container = var.enable_adot_sidecar ? [{
    name      = "aws-otel-collector"
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
    essential = false # 🌟 CRITICAL: App KHÔNG chết nếu Sidecar crash (Trả lời Câu hỏi 2)
    
    # Báo cho ADOT biết nó cần đọc config từ Environment Variable
    command = ["--config=env:AOT_CONFIG_CONTENT"]
    
    # Cấp phát resource cố định cho Sidecar (Tránh noisy neighbor với App)
    cpu    = 128  # 0.125 vCPU
    memory = 256  # 256 MB RAM (Dư dả cho limit_mib: 128 trong YAML)

    environment = [
      {
        name = "AOT_CONFIG_CONTENT"
        # 🌟 RENDER TEMPLATE: inject aws_region và sampling_rate vào YAML
        value = templatefile("${path.module}/otel-config-aws.yaml.tftpl", {
          aws_region    = var.aws_region
          sampling_rate = var.traces_sampling_rate
          service_name  = var.service_name
        })
      },
      {
        name  = "AMP_ENDPOINT"
        # prometheus_endpoint (từ SSM) = base URL: https://aps-workspaces.../workspaces/ws-xxx/
        # ADOT prometheusremotewrite cần full path kèm api/v1/remote_write
        value = "${var.amp_endpoint}api/v1/remote_write" 
      },
      # 🆕 NEW: Cho self-metrics pipeline dùng
      {
        name  = "PROJECT_NAME"
        value = var.project_name
      },
      {
        name  = "SERVICE_NAME"
        value = var.service_name
      }
    ]

    portMappings = [
      { containerPort = 4317, protocol = "tcp" }, # OTLP gRPC
      { containerPort = 4318, protocol = "tcp" }, # OTLP HTTP
      { containerPort = 13133, protocol = "tcp" }  # 🌟 Health check endpoint
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.otel[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "otel"
      }
    }
    
    # 🌟 REAL HEALTH CHECK (không còn dummy "echo 'health'")
    healthCheck = {
      # Dùng wget (có sẵn trong ADOT image dựa trên Debian) để probe endpoint
      command = [
        "CMD-SHELL",
        "wget --no-verbose --tries=1 --spider http://localhost:13133/ || exit 1"
      ]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60  # Chờ OTel collector khởi động xong (nó load config chậm hơn App)
    }
  }] : []

  container_definitions = jsonencode(concat([local.app_container], local.adot_container))
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project_name}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = local.container_definitions

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.service_name}"
    Service = var.service_name
  })
}
