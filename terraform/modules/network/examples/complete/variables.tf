#--------------------------------------------------------------
# Example Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "example-net"
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs"
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (cost-saving)"
  type        = bool
  default     = true
}
