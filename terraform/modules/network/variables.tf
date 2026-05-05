#--------------------------------------------------------------
# Network Module — Input Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name only accepts lowercase, digits, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for endpoint service names"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must match format, e.g. ap-southeast-1, us-east-1."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (must be /16)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid CIDR with /16 prefix (e.g. 10.0.0.0/16)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use (2 or 3)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost-saving) vs one per AZ (HA)"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# VPC Flow Logs
#--------------------------------------------------------------

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Log Group retention in days for flow logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a valid CloudWatch retention value."
  }
}

variable "flow_logs_cloudwatch_traffic_type" {
  description = "Traffic type for CloudWatch flow logs: ALL or REJECT. REJECT reduces cost while capturing security-relevant events."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_cloudwatch_traffic_type)
    error_message = "flow_logs_cloudwatch_traffic_type must be ALL, ACCEPT, or REJECT."
  }
}

variable "flow_logs_s3_bucket_arn" {
  description = "S3 bucket ARN for flow log archive. Empty string disables S3 destination."
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
