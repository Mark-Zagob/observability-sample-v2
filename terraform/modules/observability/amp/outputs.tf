#--------------------------------------------------------------
# Outputs — observability/amp
#--------------------------------------------------------------

output "workspace_id" {
  description = "AMP workspace ID"
  value       = aws_prometheus_workspace.this.id
}

output "workspace_arn" {
  description = "AMP workspace ARN (for IAM policy scoping)"
  value       = aws_prometheus_workspace.this.arn
}

output "prometheus_endpoint" {
  description = "AMP remote write / query endpoint URL"
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}
