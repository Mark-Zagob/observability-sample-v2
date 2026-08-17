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

output "remote_write_url" {
  description = "Full AMP RemoteWrite API endpoint (endpoint + 'api/v1/remote_write') — dùng thẳng trong ADOT/Prometheus remote_write config, không cần caller tự ghép chuỗi."
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "kms_key_arn" {
  description = "KMS CMK ARN dùng để mã hóa AMP workspace at-rest"
  value       = aws_kms_key.amp.arn
}

output "remote_write_policy_arn" {
  description = "IAM policy ARN (aps:RemoteWrite, scoped to this workspace). Caller phải attach vào ECS Task Role qua aws_iam_role_policy_attachment."
  value       = aws_iam_policy.ecs_task_remote_write.arn
}
