#--------------------------------------------------------------
# Bootstrap Migration Module — Variables
#--------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (lab, dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

#--------------------------------------------------------------
# ECS
#--------------------------------------------------------------

variable "ecs_cluster_name" {
  description = "ECS cluster name to run migration task in"
  type        = string
}

variable "migration_image" {
  description = "Docker image URI for migration task (e.g., <account>.dkr.ecr.<region>.amazonaws.com/migration:v1)"
  type        = string
}

#--------------------------------------------------------------
# Database
#--------------------------------------------------------------

variable "db_host" {
  description = "RDS hostname (without port)"
  type        = string
}

variable "db_name" {
  description = "Database name to migrate"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the DB secret"
  type        = string
}

#--------------------------------------------------------------
# Network
#--------------------------------------------------------------

variable "execution_role_arn" {
  description = "ECS task execution role ARN (for pulling images and writing logs)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Fargate task networking"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID allowing access to RDS"
  type        = string
}

#--------------------------------------------------------------
# Trigger
#--------------------------------------------------------------

variable "migration_sql_hash" {
  description = "Hash of the migration SQL file content — triggers re-run when SQL changes"
  type        = string
  default     = ""
}

#--------------------------------------------------------------
# Tags
#--------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
