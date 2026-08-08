#--------------------------------------------------------------
# Shared Environment - Provider Configuration
#--------------------------------------------------------------

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
  region  = var.aws_region
  profile = "default"

# readonly chỉ để mục đích kiểm tra tính năng assume role trong terraform nên đã comment lại
  # assume_role {
  #   role_arn     = "arn:aws:iam::730335245469:role/tud7hc-readonly-assume-role"
  #   session_name = "terraform-shared-readonly"    # ← tên bạn tự đặt
  # }

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Plane       = "Control" # ← Đánh dấu resource này thuộc Control Plane
      ManagedBy   = "terraform"
    }
  }
}

#--------------------------------------------------------------
# DR Region Provider — for cross-region backup vault
# Used by backup module's aws.dr provider alias.
#--------------------------------------------------------------
provider "aws" {
  alias   = "dr"
  region  = var.dr_region
  profile = "default"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Plane       = "Control-DR"
      ManagedBy   = "terraform"
      Purpose     = "disaster-recovery"
    }
  }
}

