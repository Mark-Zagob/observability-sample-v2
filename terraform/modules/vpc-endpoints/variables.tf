#--------------------------------------------------------------
# VPC Endpoints Module — Input Variables
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
  description = "ID of the VPC to create endpoints in"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used for Security Group ingress rules)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR notation."
  }
}

variable "route_table_ids" {
  description = "List of all route table IDs to associate with Gateway Endpoints"
  type        = list(string)

  validation {
    condition     = length(var.route_table_ids) > 0
    error_message = "At least one route table ID is required for Gateway Endpoints."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Interface Endpoint placement"
  type        = list(string)
  default     = []
}

#--------------------------------------------------------------
# Gateway Endpoint Controls
#--------------------------------------------------------------

variable "enable_s3_endpoint" {
  description = "Enable S3 Gateway Endpoint (FREE — should always be true)"
  type        = bool
  default     = true
}

variable "enable_dynamodb_endpoint" {
  description = "Enable DynamoDB Gateway Endpoint (FREE — enable if using DynamoDB)"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# Interface Endpoints (optional, costs money)
#--------------------------------------------------------------

variable "enable_interface_endpoints" {
  description = "Enable Interface VPC Endpoints (~$7.2/month per endpoint per AZ)"
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "List of AWS services to create Interface Endpoints for"
  type        = list(string)
  default = [
    "ecr.api",          # ECS image pull (API calls)
    "ecr.dkr",          # ECS image pull (Docker registry)
    "logs",             # CloudWatch Logs (container logs)
    "ssm",              # SSM Parameter Store (secrets, bastion)
    "secretsmanager",   # Secrets Manager (DB passwords)
    "sts",              # STS (IAM role assumption for ECS tasks)
    "monitoring"        # CloudWatch Metrics (custom metrics)
  ]

  validation {
    condition     = length(var.interface_endpoint_services) > 0 || !var.enable_interface_endpoints
    error_message = "interface_endpoint_services must not be empty when enable_interface_endpoints is true."
  }
}

#--------------------------------------------------------------
# S3 Endpoint Policy
#--------------------------------------------------------------

variable "s3_endpoint_policy" {
  description = "Custom IAM policy JSON for S3 Gateway Endpoint. If empty, uses default (full S3 access from VPC)."
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
