#--------------------------------------------------------------
# Loadbalancer Module — Application Load Balancer
#--------------------------------------------------------------
# Internet-facing ALB in public subnets.
# Receives HTTPS traffic from Route 53 → forwards to ECS tasks.
#--------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  # Drop invalid HTTP headers (security best practice)
  drop_invalid_header_fields = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-alb"
  })
}
