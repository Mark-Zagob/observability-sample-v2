#--------------------------------------------------------------
# Security Module — Input Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name only accepts lowercase, digits, and hyphens."
  }
}

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for internal traffic rules"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR (e.g. 10.0.0.0/16)."
  }
}

#--------------------------------------------------------------
# Application Configuration
#--------------------------------------------------------------

variable "app_port" {
  description = "Application container port (used in App SG ingress from ALB)"
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "app_health_check_port" {
  description = "Health check port if different from app_port (0 = same as app_port)"
  type        = number
  default     = 0

  validation {
    condition     = var.app_health_check_port >= 0 && var.app_health_check_port <= 65535
    error_message = "app_health_check_port must be between 0 and 65535."
  }
}

#--------------------------------------------------------------
# Bastion Configuration
#--------------------------------------------------------------

variable "enable_bastion" {
  description = "Enable bastion host resources (SG, IAM, key pair)"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDRs allowed to SSH into bastion host"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each element in allowed_ssh_cidrs must be a valid CIDR."
  }
}

variable "generate_ssh_key" {
  description = "Auto-generate SSH key pair (true for lab, false for production)"
  type        = bool
  default     = true
}

variable "public_key_path" {
  description = "Path to SSH public key file (used when generate_ssh_key = false)"
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# Data Tier Ports (consumed by Data SG)
#--------------------------------------------------------------

variable "db_ports" {
  description = "Map of database service names to their ports"
  type        = map(number)
  default = {
    postgres = 5432
    mysql    = 3306
    redis    = 6379
    kafka    = 9092
  }
}

#--------------------------------------------------------------
# Monitoring Ports (consumed by Observability SG)
#--------------------------------------------------------------

variable "monitoring_ports" {
  description = "Map of monitoring service names to their ports"
  type        = map(number)
  default = {
    prometheus    = 9090
    grafana       = 3000
    node_exporter = 9100
    loki          = 3100
    tempo         = 4317
  }
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
