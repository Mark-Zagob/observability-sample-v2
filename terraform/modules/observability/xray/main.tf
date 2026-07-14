#--------------------------------------------------------------
# Main — observability/xray
#--------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(var.common_tags, {
    Module      = "observability-xray"
    Plane       = "Control"
    Environment = var.environment
    Project     = var.project_name
  })
}

#--------------------------------------------------------------
# Custom Sampling Rule — 1 rule per service
#--------------------------------------------------------------
# Priority thấp hơn = match trước implicit "Default" rule (priority
# 10000, không thể xóa/sửa). Match theo service_name — không dùng
# wildcard "*" để tránh vô tình override sampling của service khác
# chưa được onboard vào module này.

resource "aws_xray_sampling_rule" "service" {
  for_each = var.services

  rule_name      = "${local.name_prefix}-${each.key}"
  priority       = 100
  version        = 1
  reservoir_size = var.reservoir_size
  fixed_rate     = var.fixed_rate

  service_name = each.key
  service_type = "*"
  host         = "*"
  http_method  = "*"
  url_path     = "*"
  resource_arn = "*"

  tags = merge(local.tags, { Service = each.key })
}
