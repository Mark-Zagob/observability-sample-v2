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

  # --- ADOT Sidecar Container (optional) ---
  adot_container = var.enable_adot_sidecar ? [{
    name      = "aws-otel-collector"
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
    essential = false # Don't kill the app if ADOT crashes

    command = ["--config=/etc/ecs/ecs-default-config.yaml"]

    portMappings = [
      { containerPort = 4317, protocol = "tcp" }, # OTLP gRPC
      { containerPort = 4318, protocol = "tcp" }, # OTLP HTTP
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.otel[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "otel"
      }
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
