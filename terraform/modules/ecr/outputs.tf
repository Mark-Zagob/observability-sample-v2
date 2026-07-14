#--------------------------------------------------------------
# ECR Module — Outputs
#--------------------------------------------------------------

output "repository_urls" {
  description = "Map of service name to ECR repository URL (for docker push/pull)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN (for IAM policies)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
