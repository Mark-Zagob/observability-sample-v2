#--------------------------------------------------------------
# Loadbalancer Module — Listeners
#--------------------------------------------------------------
# HTTPS (443): Primary listener with ACM certificate.
#   Default action: fixed 404 (services add rules via priority).
# HTTP (80):  Redirects all traffic to HTTPS (301).
#--------------------------------------------------------------

# --- HTTPS Listener (443) ---

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\": \"not_found\", \"message\": \"No route matched\"}"
      status_code  = "404"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-https"
  })
}

# --- HTTP Listener (80) → Redirect to HTTPS ---

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-http-redirect"
  })
}
