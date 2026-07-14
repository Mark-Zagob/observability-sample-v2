#--------------------------------------------------------------
# ACM Module — Outputs
#--------------------------------------------------------------

output "certificate_arn" {
  description = "ARN of the validated ACM certificate (use in ALB HTTPS listener)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "certificate_domain" {
  description = "Primary domain name of the certificate"
  value       = aws_acm_certificate.this.domain_name
}
