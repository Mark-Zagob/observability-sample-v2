#--------------------------------------------------------------
# Loadbalancer Module — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for target groups"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB placement"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID for ALB"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
}

variable "services" {
  description = "Map of ALB-facing services with routing config"
  type = map(object({
    port          = number
    health_path   = string
    path_patterns = list(string)
    priority      = number
  }))
  default = {}
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection (true for production)"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
