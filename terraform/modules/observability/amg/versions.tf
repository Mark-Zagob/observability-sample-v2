#--------------------------------------------------------------
# Module: observability/amg — Amazon Managed Grafana
#--------------------------------------------------------------
# Tạo AMG workspace với SSO authentication, IAM role cho
# data source access (AMP, X-Ray, CloudWatch), và Service Account
# cho Terraform automation (Grafana Provider).
#
# Usage:
#   module "amg" {
#     source                  = "../../modules/observability/amg"
#     project_name            = "obs"
#     environment             = "lab"
#     aws_region              = "ap-southeast-2"
#     amp_workspace_arn       = module.amp.workspace_arn
#     admin_user_id           = "xxxx-xxxx-xxxx"  # optional
#   }
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}
