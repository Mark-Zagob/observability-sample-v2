#--------------------------------------------------------------
# Bootstrap — Terraform State Infrastructure
#--------------------------------------------------------------
# Production-grade backend: S3 + DynamoDB + KMS
# Run this module ONCE to create the state backend.
# Uses LOCAL state (chicken-and-egg: can't store state in S3
# before S3 exists).
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform plan
#   terraform apply
#
# After apply, update environments/*/backend.tf with the
# output values, then run:
#   cd terraform/environments/shared
#   terraform init -migrate-state
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ⚠️ LOCAL state — intentional for bootstrap only
  # This module manages ~5 resources. If state is lost,
  # re-import with: terraform import aws_s3_bucket.state <bucket-name>
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
      Purpose   = "state-management"
    }
  }
}
