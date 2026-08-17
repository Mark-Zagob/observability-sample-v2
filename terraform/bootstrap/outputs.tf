#--------------------------------------------------------------
# Bootstrap — Outputs
#--------------------------------------------------------------
# Copy these values to environments/*/backend.tf
#--------------------------------------------------------------

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state — use in backend.tf"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking — use in backend.tf"
  value       = aws_dynamodb_table.locks.name
}

output "kms_key_arn" {
  description = "KMS key ARN for state encryption"
  value       = aws_kms_key.state.arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = aws_kms_alias.state.name
}

output "log_bucket_name" {
  description = "S3 access log bucket name"
  value       = aws_s3_bucket.logs.id
}

output "aws_region" {
  description = "AWS region for backend config"
  value       = var.aws_region
}

#--------------------------------------------------------------
# Helper: Backend Config Snippet
#--------------------------------------------------------------
output "backend_config_snippet" {
  description = "Copy this into your backend.tf"
  value       = <<-EOT

    # Paste into environments/*/backend.tf:
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "ENVIRONMENT/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.locks.name}"
        encrypt        = true
        kms_key_id     = "${aws_kms_key.state.arn}"
      }
    }

  EOT
}
