#--------------------------------------------------------------
# Variables — observability/amp
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "project_name must be between 1 and 20 characters."
  }
}

variable "environment" {
  description = "Environment name (lab, dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "lab"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, lab."
  }
}

variable "sns_critical_arn" {
  description = "ARN of SNS topic for critical alarms (cardinality bomb)"
  type        = string
}

variable "active_series_threshold" {
  description = "Threshold for AMP ActiveSeries cardinality alarm. Lab=10000, Prod=100000."
  type        = number
  default     = 10000

  validation {
    condition     = var.active_series_threshold > 0
    error_message = "active_series_threshold must be positive."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS Task Role to explicitly allow KMS usage for SigV4 remote write"
  type        = string
}
