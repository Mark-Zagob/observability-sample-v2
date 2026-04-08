variable "aws_region" {
    type = string
    description = "regions for setting up environments"
}

variable "project_name" {
  type = string
  description = "define projects belong to"
}

variable "env_deploy" {
  type = string
  description = "environment for implementing"
}

variable "vpc_cidr" {
  type = string
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr phải là CIDR hợp lệ với prefix /16 (ví dụ: 10.0.0.0/16)"
  }
}

variable "single_nat_gateway" {
  type = bool
  default = true
}