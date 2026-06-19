#--------------------------------------------------------------
# ECR Module — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name only accepts lowercase, digits, and hyphens."
  }
}

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)

  validation {
    condition     = length(var.repository_names) > 0
    error_message = "At least one repository name is required."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability setting (MUTABLE for dev/lab, IMMUTABLE for production)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image vulnerability scanning on push (free basic scanning)"
  type        = bool
  default     = true
}

variable "max_tagged_images" {
  description = "Maximum number of tagged images to keep per repository"
  type        = number
  default     = 10
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images are expired"
  type        = number
  default     = 7
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
