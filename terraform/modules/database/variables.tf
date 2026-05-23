#--------------------------------------------------------------
# Database Module — Input Variables
#--------------------------------------------------------------

#--------------------------------------------------------------
# Required — from upstream modules
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod, lab)"
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["dev", "staging", "prod", "lab"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, lab."
  }
}

variable "vpc_id" {
  description = "VPC ID for RDS subnet group"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of data subnet IDs for RDS placement (minimum 2 AZs)"
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_ids) >= 2
    error_message = "At least 2 data subnets required for RDS subnet group."
  }
}

variable "data_security_group_id" {
  description = "Security Group ID for data layer (allows app → DB traffic)"
  type        = string
}

#--------------------------------------------------------------
# RDS Instance Configuration
#--------------------------------------------------------------

variable "engine_version" {
  description = "PostgreSQL engine version (check region availability: aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion')"
  type        = string
  default     = "16.6"
}

variable "instance_class" {
  description = "RDS instance class (e.g., db.t3.micro, db.t3.medium)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "orders"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB (0 = disabled)"
  type        = number
  default     = 50
}

#--------------------------------------------------------------
# Production Toggles — vary per environment
#--------------------------------------------------------------

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = false
}

variable "read_replica_count" {
  description = "Number of read replicas (0=none, 1=staging, 2=production)"
  type        = number
  default     = 0

  validation {
    condition     = var.read_replica_count >= 0 && var.read_replica_count <= 5
    error_message = "read_replica_count must be between 0 and 5."
  }
}

variable "replica_instance_class" {
  description = "Instance class for read replicas (can differ from primary for analytics)"
  type        = string
  default     = "db.t3.micro"
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0 = disabled)"
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the RDS instance"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (true for lab/dev, false for prod)"
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Auto-apply minor engine upgrades during maintenance window (security patches)"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately (true for lab) or during maintenance window (false for prod)"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# Monitoring
#--------------------------------------------------------------

variable "enhanced_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 = disabled, 1/5/10/15/30/60)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enhanced_monitoring_interval)
    error_message = "enhanced_monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for CPU, storage, and connection monitoring"
  type        = bool
  default     = true
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization threshold for alarm (%)"
  type        = number
  default     = 80
}

variable "alarm_free_storage_threshold" {
  description = "Free storage space threshold for alarm (bytes)"
  type        = number
  default     = 2000000000 # 2 GB
}

variable "alarm_connections_threshold" {
  description = "Database connections threshold for alarm (varies by instance class: t3.micro≈87, t3.small≈174, t3.medium≈348)"
  type        = number
  default     = 70
}

variable "secret_rotation_days" {
  description = "Alert when DB password has not been rotated in this many days (SOC2/HIPAA: 90 days)"
  type        = number
  default     = 90
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications (empty = no notifications)"
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
