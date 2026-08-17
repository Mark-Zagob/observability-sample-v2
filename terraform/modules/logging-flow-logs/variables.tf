#--------------------------------------------------------------
# Logging Module — Input Variables
#--------------------------------------------------------------

#--------------------------------------------------------------
# Required — from upstream modules / environment
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name only accepts lowercase, digits, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod, lab)"
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["dev", "staging", "prod", "lab"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, lab."
  }
}

#--------------------------------------------------------------
# S3 Lifecycle Configuration
#--------------------------------------------------------------

variable "flow_logs_glacier_transition_days" {
  description = "Days before flow logs transition to Glacier Flexible Retrieval"
  type        = number
  default     = 90

  validation {
    condition     = var.flow_logs_glacier_transition_days >= 30
    error_message = "Glacier transition must be at least 30 days."
  }
}

variable "flow_logs_expiration_days" {
  description = "Days before flow logs are permanently deleted"
  type        = number
  default     = 365

  validation {
    condition     = var.flow_logs_expiration_days >= 90
    error_message = "Flow logs expiration must be at least 90 days."
  }
}

#--------------------------------------------------------------
# Athena Configuration
#--------------------------------------------------------------

variable "athena_query_result_retention_days" {
  description = "Days to retain Athena query results in S3"
  type        = number
  default     = 7
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
