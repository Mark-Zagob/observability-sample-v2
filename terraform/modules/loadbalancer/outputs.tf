#--------------------------------------------------------------
# Loadbalancer Module — Outputs
#--------------------------------------------------------------

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB (for Route 53 alias record)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias record)"
  value       = aws_lb.this.zone_id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "target_group_arns" {
  description = "Map of service name to target group ARN (for ECS service registration)"
  value       = { for name, tg in aws_lb_target_group.this : name => tg.arn }
}
