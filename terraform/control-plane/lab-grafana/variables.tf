#--------------------------------------------------------------
# Grafana Config — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "obs"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "aws_region" {
  description = "AWS region (must match control-plane)"
  type        = string
  default     = "ap-southeast-2"
}
