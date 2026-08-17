#--------------------------------------------------------------
# ACM Module — Variables
#--------------------------------------------------------------

variable "domain_name" {
  description = "Primary domain name for the ACM certificate (e.g., app.example.com)"
  type        = string
}

variable "zone_id" {
  description = "Route 53 Hosted Zone ID for DNS validation"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names for the certificate (e.g., [\"*.example.com\"])"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
