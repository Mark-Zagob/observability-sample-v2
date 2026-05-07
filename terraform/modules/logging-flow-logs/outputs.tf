#--------------------------------------------------------------
# Logging Module — Outputs
#--------------------------------------------------------------

# S3 Bucket
output "flow_logs_bucket_arn" {
  description = "ARN of the S3 bucket for VPC Flow Logs"
  value       = aws_s3_bucket.flow_logs.arn
}

output "flow_logs_bucket_id" {
  description = "Name/ID of the S3 bucket for VPC Flow Logs"
  value       = aws_s3_bucket.flow_logs.id
}

# KMS
output "flow_logs_kms_key_arn" {
  description = "ARN of the KMS key used for flow logs S3 encryption"
  value       = aws_kms_key.flow_logs_s3.arn
}

output "flow_logs_kms_key_id" {
  description = "ID of the KMS key used for flow logs S3 encryption"
  value       = aws_kms_key.flow_logs_s3.key_id
}

# Athena
output "athena_database_name" {
  description = "Glue catalog database name for Athena queries"
  value       = aws_glue_catalog_database.flow_logs.name
}

output "athena_table_name" {
  description = "Glue catalog table name for VPC Flow Logs"
  value       = aws_glue_catalog_table.flow_logs.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name for flow log queries"
  value       = aws_athena_workgroup.flow_logs.name
}
