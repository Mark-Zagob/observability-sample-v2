#--------------------------------------------------------------
# DATA PLANE - ORDER SERVICE VARIABLES
# Đây là "Hợp đồng" để App Team khai báo cấu hình service
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name (must match Control Plane)"
  type        = string
  default     = "obs"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "service_name" {
  description = "Name of the microservice"
  type        = string
  default     = "order-service"
}

# 🌟 BIẾN QUAN TRỌNG: App Team tự quản lý version của họ
variable "image_tag" {
  description = "Docker image tag to deploy (e.g., git-sha, v1.2.3)"
  type        = string
  # Không nên để default, bắt buộc App Team phải khai báo rõ ràng
}

variable "container_port" {
  description = "Port the application listens on"
  type        = number
  default     = 5001
}

# Task Sizing (App Team tự request resource họ cần)
variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}
