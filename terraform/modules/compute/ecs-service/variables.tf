#--------------------------------------------------------------
# ECS Service Module — Variables
#--------------------------------------------------------------
# Reusable module: instantiate once per microservice.
# Supports both ALB-facing services and background workers.
#--------------------------------------------------------------

#--------------------------------------------------------------
# Required
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "service_name" {
  description = "Name of the microservice (e.g., payment-service)"
  type        = string
}

variable "cluster_id" {
  description = "ECS Cluster ID to run this service in"
  type        = string
}

variable "image" {
  description = "Docker image URI (e.g., 123456.dkr.ecr.region.amazonaws.com/repo:tag)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "subnets" {
  description = "Subnet IDs for ECS task placement (private subnets)"
  type        = list(string)
}

variable "security_groups" {
  description = "Security Group IDs for ECS tasks"
  type        = list(string)
}

variable "execution_role_arn" {
  description = "IAM role ARN for ECS agent (ECR pull, CloudWatch logs)"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for application code (S3, SQS, Secrets Manager)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch Logs"
  type        = string
}

#--------------------------------------------------------------
# Task sizing
#--------------------------------------------------------------

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB (512 = 0.5 GB)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of task instances to run"
  type        = number
  default     = 1
}

#--------------------------------------------------------------
# Load Balancer (optional — disable for workers)
#--------------------------------------------------------------

variable "enable_load_balancer" {
  description = "Register service with ALB target group (false for Kafka workers)"
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ALB target group ARN (required when enable_load_balancer = true)"
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# Service Discovery (Cloud Map)
#--------------------------------------------------------------

variable "enable_service_discovery" {
  description = "Register service in Cloud Map namespace"
  type        = bool
  default     = true
}

variable "namespace_id" {
  description = "Cloud Map namespace ID (from ecs-cluster module)"
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# ADOT Sidecar (OpenTelemetry)
#--------------------------------------------------------------

variable "enable_adot_sidecar" {
  description = "Add AWS Distro for OpenTelemetry collector sidecar"
  type        = bool
  default     = false
}

#--------------------------------------------------------------
# Health Check
#--------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path for container health check. Use /health/live (liveness) when deps like Redis are not deployed, /health (readiness) when all deps are available."
  type        = string
  default     = "/health/live"
}

#--------------------------------------------------------------
# ECS Exec (shell into running containers)
#--------------------------------------------------------------

variable "enable_execute_command" {
  description = "Enable ECS Exec to shell into running containers (requires SSM permissions on task role)"
  type        = bool
  default     = true
}

variable "enable_app_error_metric" {
  description = "Create CloudWatch Metric Filter to count app-level ERROR logs. Alarm is in control-plane."
  type        = bool
  default     = true
}

#--------------------------------------------------------------
# Application Configuration
#--------------------------------------------------------------

variable "environment" {
  description = "Map of environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of secrets (name → Secrets Manager ARN or SSM parameter ARN)"
  type        = map(string)
  default     = {}
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "amp_endpoint" {
  description = "Amazon Managed Prometheus endpoint URL (injected into ADOT sidecar)"
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# Graceful Shutdown Configuration (Fix BOMB #1)
#--------------------------------------------------------------
variable "stop_timeout" {
  description = "Seconds to wait for container to stop gracefully before SIGKILL. Must be > Gunicorn graceful_timeout (25s). AWS max: 120s."
  type        = number
  default     = 60  # 🌟 Production standard: 60s
  
  validation {
    condition     = var.stop_timeout >= 30 && var.stop_timeout <= 120
    error_message = "stopTimeout must be between 30 and 120 seconds (AWS Fargate limit)."
  }
}

variable "traces_sampling_rate" {
  description = "Percentage of traces to sample (0-100). Set 100 for dev/lab, 10 for prod."
  type        = number
  default     = 100
  
  validation {
    condition     = var.traces_sampling_rate >= 0 && var.traces_sampling_rate <= 100
    error_message = "traces_sampling_rate must be between 0 and 100."
  }
}
