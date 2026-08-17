#--------------------------------------------------------------
# Loadbalancer Module — Target Groups + Listener Rules
#--------------------------------------------------------------
# Dynamic creation: one target group + one listener rule per
# entry in var.services map.
#
# ECS services register into these target groups via
# aws_ecs_service.load_balancer block.
#--------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name        = "${var.project_name}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for ECS Fargate

  health_check {
    enabled             = true
    path                = each.value.health_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  # Allow time for in-flight requests during deployments
  deregistration_delay = 30

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-tg-${each.key}"
    Service = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

#--------------------------------------------------------------
# Listener Rules — Path-based routing
#--------------------------------------------------------------

resource "aws_lb_listener_rule" "this" {
  for_each = var.services

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-rule-${each.key}"
    Service = each.key
  })
}
