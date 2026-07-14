#--------------------------------------------------------------
# Variables — observability/xray
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

variable "services" {
  description = "Set of service names (ECS service name = X-Ray service_name) cần custom sampling rule riêng"
  type        = set(string)
}

variable "reservoir_size" {
  description = "Số request/giây được trace 100% (không bị sample) trước khi áp dụng fixed_rate"
  type        = number
  default     = 1

  validation {
    condition     = var.reservoir_size >= 0
    error_message = "reservoir_size must be >= 0."
  }
}

variable "fixed_rate" {
  description = "Tỷ lệ sample cho request vượt reservoir (0.0 - 1.0). Lab: 0.1-0.5 để quan sát đầy đủ Chaos Drills. Prod: 0.05 để tiết kiệm chi phí X-Ray (billed per trace)."
  type        = number
  default     = 0.1

  validation {
    condition     = var.fixed_rate >= 0 && var.fixed_rate <= 1
    error_message = "fixed_rate must be between 0.0 and 1.0."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
