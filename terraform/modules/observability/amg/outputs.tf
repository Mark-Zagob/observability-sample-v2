#--------------------------------------------------------------
# Outputs — observability/amg
#--------------------------------------------------------------

output "workspace_id" {
  description = "AMG workspace ID"
  value       = aws_grafana_workspace.this.id
}

output "workspace_endpoint" {
  description = "AMG workspace URL (open in browser to access Grafana)"
  value       = aws_grafana_workspace.this.endpoint
}

output "workspace_arn" {
  description = "AMG workspace ARN"
  value       = aws_grafana_workspace.this.arn
}

output "service_account_token" {
  description = "Grafana Service Account token for Terraform Provider authentication"
  value       = aws_grafana_workspace_service_account_token.terraform.key
  sensitive   = true
}

output "iam_role_arn" {
  description = "IAM Role ARN used by the Grafana workspace"
  value       = aws_iam_role.this.arn
}
