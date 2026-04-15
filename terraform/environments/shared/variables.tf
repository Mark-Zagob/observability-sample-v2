#--------------------------------------------------------------
# Shared Environment - Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
}

#--------------------------------------------------------------
# Network
#--------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = 1 NAT (save cost), false = 1 NAT per AZ (HA)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# VPC Endpoints (uncomment khi bật module vpc-endpoints)
#--------------------------------------------------------------
# variable "enable_interface_endpoints" {
#   description = "Enable Interface VPC Endpoints (costs money)"
#   type        = bool
#   default     = false
# }

#--------------------------------------------------------------
# Security
#--------------------------------------------------------------
variable "app_port" {
  description = "Application container port"
  type        = number
  default     = 8080
}

variable "enable_bastion" {
  description = "Enable bastion host resources (SG, IAM, Key Pair)"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = []
}

variable "generate_ssh_key" {
  description = "Auto-generate SSH key pair (true for lab, false for production)"
  type        = bool
  default     = true
}
