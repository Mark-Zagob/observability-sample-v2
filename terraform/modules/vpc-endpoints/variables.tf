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

variable "aws_region" {
  description = "AWS region for endpoint service names"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must match format, e.g. ap-southeast-1, us-east-1."
  }
}

variable "vpc_id" {
  description = "ID of the VPC to create endpoints in"
  type        = string
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
    "ecr.api",
    "ecr.dkr",
    "logs",
    "ssm",
    "secretsmanager",
    "sts",
    "monitoring"
  ]
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
