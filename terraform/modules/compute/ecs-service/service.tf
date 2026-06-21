#--------------------------------------------------------------
# ECS Service Module — ECS Service
#--------------------------------------------------------------
# The ECS Service keeps N tasks running (self-healing).
# Supports:
#   - ALB registration (for HTTP-facing services)
#   - Cloud Map registration (for service-to-service discovery)
#   - Rolling deployment (default ECS strategy)
#--------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # ECS Exec — shell into running containers for debugging
  enable_execute_command = var.enable_execute_command

  # Tasks run in private subnets, no public IP
  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_groups
    assign_public_ip = false
  }

  # ALB registration (optional — disabled for workers)
  dynamic "load_balancer" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  # Cloud Map registration (optional)
  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.this[0].arn
    }
  }

  # Rolling deployment — wait for new tasks to be healthy before stopping old
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # 👇 FIX BOM #2: The Rollback Shield
  deployment_circuit_breaker {
    enable   = true
    rollback = true # Tự động hủy deploy và quay lại Task Definition cũ nếu task mới fail
  }

  # Wait for ALB health check before considering deployment successful
  health_check_grace_period_seconds = var.enable_load_balancer ? 60 : null

  # Allow terraform to update task definition without forcing replacement
  force_new_deployment = true

  # Ignore desired_count changes from auto-scaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.service_name}"
    Service = var.service_name
  })
}
