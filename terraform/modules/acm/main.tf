#--------------------------------------------------------------
# ACM Module — Certificate + DNS Validation
#--------------------------------------------------------------
# Creates an ACM certificate with automatic DNS validation
# via Route 53. Certificate is FREE and auto-renews.
#
# Note: Route 53 A record (alias → ALB) is created in main.tf
# to avoid circular dependency between this module and loadbalancer.
#--------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.common_tags, {
    Name = var.domain_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

#--------------------------------------------------------------
# DNS Validation Records
#--------------------------------------------------------------
# ACM provides CNAME records that must exist in Route 53
# to prove domain ownership. Terraform auto-creates them.
#--------------------------------------------------------------

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}

#--------------------------------------------------------------
# Wait for Validation to Complete
#--------------------------------------------------------------
# This resource blocks until AWS confirms the certificate
# is validated and ready to use (~2-5 minutes).
#--------------------------------------------------------------

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
