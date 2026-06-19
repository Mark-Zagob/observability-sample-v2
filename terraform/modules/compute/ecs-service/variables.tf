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
