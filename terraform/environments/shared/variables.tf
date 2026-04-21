#--------------------------------------------------------------
# Shared Environment - Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name for tagging and resource identification"
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["dev", "staging", "prod", "lab"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, lab."
  }
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
# VPC Endpoints
#--------------------------------------------------------------
variable "enable_interface_endpoints" {
  description = "Enable Interface VPC Endpoints (~$7.2/month per endpoint per AZ)"
  type        = bool
  default     = false
}

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

#--------------------------------------------------------------
# Database (RDS PostgreSQL)
#--------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "orders"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB"
  type        = number
  default     = 50
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Days to retain automated backups (0-35)"
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Prevent accidental deletion of RDS instance"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on destroy (true for lab)"
  type        = bool
  default     = true
}

variable "db_enhanced_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 = disabled)"
  type        = number
  default     = 0
}

variable "db_enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for database monitoring"
  type        = bool
  default     = true
}
