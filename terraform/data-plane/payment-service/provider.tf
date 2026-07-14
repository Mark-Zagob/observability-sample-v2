terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-southeast-2" # Hoặc dùng var.aws_region
  profile = "default"
  default_tags {
    tags = {
      Project     = "obs"
      Environment = "lab"
      Plane       = "Data"       # ← Đánh dấu resource này thuộc Data Plane
      Service     = "payment"    # ← Đánh dấu owner
      ManagedBy   = "terraform"
    }
  }
}