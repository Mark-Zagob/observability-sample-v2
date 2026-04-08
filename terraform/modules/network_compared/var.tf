variable "avai_zones" {
    type = list(string)
}

variable "project_name" {
  type = string
}

variable "env_deploy" {
  type = string
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


variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}