#--------------------------------------------------------------
# Security Module - Input Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for internal traffic rules"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into bastion (your IP)"
  type        = string
  default     = "0.0.0.0/0" # Override with your IP in tfvars
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
