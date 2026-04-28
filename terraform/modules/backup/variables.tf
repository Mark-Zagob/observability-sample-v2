#--------------------------------------------------------------
# Backup Module — Input Variables
#--------------------------------------------------------------

#--------------------------------------------------------------
# Required — from upstream modules / environment
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

#--------------------------------------------------------------
# Backup Vault Configuration
#--------------------------------------------------------------

variable "vault_lock_mode" {
  description = "Vault lock mode: governance (admin can override) or compliance (immutable, even root cannot delete)"
  type        = string
  default     = "governance"

  validation {
    condition     = contains(["governance", "compliance"], var.vault_lock_mode)
    error_message = "vault_lock_mode must be 'governance' or 'compliance'."
  }
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention enforced by vault lock (days)"
  type        = number
  default     = 1
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention enforced by vault lock (days)"
  type        = number
  default     = 365
}

variable "vault_lock_changeable_days" {
  description = "Number of days before vault lock becomes immutable (only for compliance mode, 3-36500)"
  type        = number
  default     = 3

  validation {
    condition     = var.vault_lock_changeable_days >= 3
    error_message = "vault_lock_changeable_days must be >= 3."
  }
}

#--------------------------------------------------------------
# Backup Plan — Daily
#--------------------------------------------------------------

variable "daily_schedule" {
  description = "Cron expression for daily backup schedule (UTC)"
  type        = string
  default     = "cron(0 3 * * ? *)" # 3:00 AM UTC daily
}

variable "daily_retention_days" {
  description = "Days to retain daily backups"
  type        = number
  default     = 35

  validation {
    condition     = var.daily_retention_days >= 1 && var.daily_retention_days <= 36500
    error_message = "daily_retention_days must be between 1 and 36500."
  }
}

variable "daily_cold_storage_after_days" {
  description = "Move daily backups to cold storage after N days (0 = disabled)"
  type        = number
  default     = 0
}

#--------------------------------------------------------------
# Backup Plan — Monthly
#--------------------------------------------------------------

variable "enable_monthly_plan" {
  description = "Enable monthly long-term retention backup plan"
  type        = bool
  default     = true
}

variable "monthly_schedule" {
  description = "Cron expression for monthly backup schedule (UTC)"
  type        = string
  default     = "cron(0 3 1 * ? *)" # 1st of month, 3:00 AM UTC
}

variable "monthly_retention_days" {
  description = "Days to retain monthly backups"
  type        = number
  default     = 365
}

variable "monthly_cold_storage_after_days" {
  description = "Move monthly backups to cold storage after N days (0 = disabled)"
  type        = number
  default     = 30
}

#--------------------------------------------------------------
# Cross-Region Copy (DR Tier 1 Foundation)
#--------------------------------------------------------------

variable "enable_cross_region_copy" {
  description = "Enable cross-region backup copy to DR region"
  type        = bool
  default     = true
}

variable "cross_region_copy_retention_days" {
  description = "Days to retain cross-region backup copies"
  type        = number
  default     = 35
}

#--------------------------------------------------------------
# Backup Selection — Tag-Based
#--------------------------------------------------------------

variable "selection_tag_key" {
  description = "Tag key used to auto-discover resources for backup"
  type        = string
  default     = "Backup"
}

variable "selection_tag_value" {
  description = "Tag value that triggers backup protection"
  type        = string
  default     = "true"
}

#--------------------------------------------------------------
# Notifications
#--------------------------------------------------------------

variable "notification_email" {
  description = "Email address for backup failure notifications (empty = no email subscription)"
  type        = string
  default     = ""
}

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for backup job failures"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
