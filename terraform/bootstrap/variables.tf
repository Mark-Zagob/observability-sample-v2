#--------------------------------------------------------------
# Bootstrap — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "obs"
}

variable "aws_region" {
  description = "AWS region for state infrastructure"
  type        = string
  default     = "ap-southeast-2"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state (must be globally unique)"
  type        = string
  default     = "" # Will be auto-generated if empty

  validation {
    condition     = var.state_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must follow S3 naming rules."
  }
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-state-locks"
}

variable "log_retention_days" {
  description = "Days to retain S3 access logs"
  type        = number
  default     = 90
}

variable "state_retention_days" {
  description = "Days to retain old state versions (noncurrent)"
  type        = number
  default     = 90
}
