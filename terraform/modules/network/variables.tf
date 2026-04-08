#--------------------------------------------------------------
# Network Module - Input Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  # [FIX #5] Validation: chặn tên rỗng hoặc có ký tự đặc biệt
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name chỉ chấp nhận lowercase, số và dấu gạch ngang."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string

  # [FIX #5] Validation: format region hợp lệ
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region phải đúng format, ví dụ: ap-southeast-1, us-east-1"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  # [FIX #5] Validation: chỉ chấp nhận /16 để cidrsubnet(8) tạo /24
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr phải là CIDR hợp lệ với prefix /16 (ví dụ: 10.0.0.0/16)"
  }
}

# NOTE: Không còn public/private/data_subnet_cidrs
# → Module tự tính bằng cidrsubnet() trong locals (main.tf)
# → Đảm bảo CIDRs luôn khớp với vpc_cidr, không bao giờ bị conflict

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost-saving) vs one per AZ (HA)"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# VPC Flow Logs
#--------------------------------------------------------------
variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch (learn network debugging)"
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# VPC Interface Endpoints (optional, costs money)
#--------------------------------------------------------------
variable "enable_interface_endpoints" {
  description = "Enable Interface VPC Endpoints (costs ~$7.2/month per endpoint per AZ)"
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "List of AWS services to create Interface Endpoints for"
  type        = list(string)
  default = [
    "ecr.api",        # ECR API calls
    "ecr.dkr",        # ECR Docker image pull
    "logs",           # CloudWatch Logs
    "ssm",            # Systems Manager
    "secretsmanager", # Secrets Manager
    "sts",            # STS (IRSA, role assumption)
    "monitoring"      # CloudWatch Metrics
  ]
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
