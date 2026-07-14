#--------------------------------------------------------------
# Outputs — observability/xray
#--------------------------------------------------------------

output "sampling_rule_names" {
  description = "Map service_name => X-Ray sampling rule name đã tạo"
  value       = { for k, v in aws_xray_sampling_rule.service : k => v.rule_name }
}

output "sampling_rule_arns" {
  description = "Map service_name => X-Ray sampling rule ARN đã tạo"
  value       = { for k, v in aws_xray_sampling_rule.service : k => v.arn }
}
