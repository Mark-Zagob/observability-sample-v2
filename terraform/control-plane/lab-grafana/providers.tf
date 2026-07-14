#--------------------------------------------------------------
# Grafana Config — Providers
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "default"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Plane       = "Control"
      Component   = "grafana-config"
      ManagedBy   = "terraform"
    }
  }
}

#--------------------------------------------------------------
# Grafana Provider — reads AMG endpoint + token from SSM
#--------------------------------------------------------------
# SSM = "Service Catalog" pattern (giống data-plane đọc control-plane).
# Ưu điểm so với terraform_remote_state:
#   - Không cần s3:GetObject trên toàn bộ state file
#   - Token dùng SecureString + KMS (không plaintext trong S3)
#   - Decoupled: không hardcode S3 bucket/key
#--------------------------------------------------------------

data "aws_ssm_parameter" "amg_endpoint" {
  name = "/${var.project_name}/${var.environment}/observability/amg_endpoint"
}

data "aws_ssm_parameter" "amg_service_account_token" {
  name            = "/${var.project_name}/${var.environment}/observability/amg_service_account_token"
  with_decryption = true
}

provider "grafana" {
  url  = "https://${data.aws_ssm_parameter.amg_endpoint.value}"
  auth = data.aws_ssm_parameter.amg_service_account_token.value
}
