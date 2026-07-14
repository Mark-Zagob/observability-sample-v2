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

variable "app_ports" {
  description = "Map of service names to their container ports (used in ALB→App SG rules)"
  type        = map(number)
  default = {
    web-ui          = 8080
    api-gateway     = 5000
    order-service   = 5001
    payment-service = 5002
  }

  validation {
    condition     = alltrue([for port in values(var.app_ports) : port > 0 && port <= 65535])
    error_message = "All ports in app_ports must be between 1 and 65535."
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
# KMS Configuration
#--------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt secrets. If empty, uses wildcard with kms:ViaService condition."
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
