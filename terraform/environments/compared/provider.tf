terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

#####

provider "aws" {
  region = var.aws_region
  profile = "default"
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.env_deploy
      ManagedBy   = "terraform"
    }
  }
}