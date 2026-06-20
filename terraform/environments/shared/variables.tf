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
variable "app_ports" {
  description = "Map of service names to container ports"
  type        = map(number)
  default = {
    web-ui          = 8080
    api-gateway     = 5000
    order-service   = 5001
    payment-service = 5002
  }
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

variable "db_auto_minor_version_upgrade" {
  description = "Auto-apply minor engine upgrades (security patches)"
  type        = bool
  default     = true
}

variable "db_apply_immediately" {
  description = "Apply RDS changes immediately or during maintenance window"
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

#--------------------------------------------------------------
# DR Region
#--------------------------------------------------------------

variable "dr_region" {
  description = "AWS region for disaster recovery (cross-region backup copy)"
  type        = string
  default     = "ap-southeast-1" # Singapore — nearest to primary (Sydney)
}

#--------------------------------------------------------------
# Backup (AWS Backup)
#--------------------------------------------------------------

variable "backup_vault_lock_mode" {
  description = "Vault lock mode: governance or compliance"
  type        = string
  default     = "governance"
}

variable "backup_daily_retention_days" {
  description = "Days to retain daily backups"
  type        = number
  default     = 35
}

variable "backup_enable_monthly_plan" {
  description = "Enable monthly long-term backup plan"
  type        = bool
  default     = true
}

variable "backup_monthly_retention_days" {
  description = "Days to retain monthly backups"
  type        = number
  default     = 365
}

variable "backup_enable_cross_region_copy" {
  description = "Enable cross-region backup copy to DR region"
  type        = bool
  default     = true
}

variable "backup_cross_region_retention_days" {
  description = "Days to retain cross-region backup copies"
  type        = number
  default     = 35
}

variable "backup_notification_email" {
  description = "Email for backup failure notifications (empty = no email)"
  type        = string
  default     = ""
}

variable "backup_enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for backup job failures"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# ECR
#--------------------------------------------------------------

variable "ecr_repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default = [
    "web-ui",
    "api-gateway",
    "order-service",
    "payment-service",
    "notification-service",
    "inventory-service"
  ]
}

variable "image_tags" {
  description = "Map of service name to image tag (versioned, no :latest in production)"
  type        = map(string)
  default = {
    web-ui               = "v1"
    api-gateway          = "v1"
    order-service        = "v1"
    payment-service      = "v1"
    notification-service = "v1"
    inventory-service    = "v1"
  }
}

#--------------------------------------------------------------
# ACM / DNS
#--------------------------------------------------------------

variable "domain_name" {
  description = "Domain name for ACM certificate and Route 53 A record"
  type        = string
}

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name (e.g., example.com)"
  type        = string
}

#--------------------------------------------------------------
# Loadbalancer
#--------------------------------------------------------------

variable "alb_services" {
  description = "Map of ALB-facing services with routing config"
  type = map(object({
    port          = number
    health_path   = string
    path_patterns = list(string)
    priority      = number
  }))
  default = {}
}
