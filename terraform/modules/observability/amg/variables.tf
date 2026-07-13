#--------------------------------------------------------------
# Variables — observability/amg
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

variable "aws_region" {
  description = "AWS region for data source configuration"
  type        = string
}

variable "amp_workspace_arn" {
  description = "ARN of the AMP workspace — used to scope Grafana IAM read policy"
  type        = string
}

variable "grafana_version" {
  description = "Grafana version for the AMG workspace"
  type        = string
  default     = "10.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.grafana_version))
    error_message = "grafana_version must be in format 'X.Y' (e.g., '10.4')."
  }
}

variable "admin_user_id" {
  description = <<-EOT
    IAM Identity Center (SSO) User ID to assign ADMIN role.
    Leave empty to skip role assignment (assign later via Console).
    Get via: aws identitystore list-users --identity-store-id <id>
  EOT
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
