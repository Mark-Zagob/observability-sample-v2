#--------------------------------------------------------------
# ECS Cluster Module — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Cloud Map namespace"
  type        = string
}

variable "namespace_name" {
  description = "Private DNS namespace for service discovery (e.g., ecommerce.local)"
  type        = string
  default     = "ecommerce.local"
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
