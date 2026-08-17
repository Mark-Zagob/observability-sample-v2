#--------------------------------------------------------------
# Module: observability/xray — X-Ray Custom Sampling Rules
#--------------------------------------------------------------
# AWS X-Ray mặc định dùng implicit "Default" rule: reservoir=1 req/s +
# fixed_rate=5% cho MỌI service — không đủ visibility khi chạy Chaos
# Drills (traffic thấp → hầu hết requests bị drop trước khi trace).
#
# Module này tạo custom sampling rule cho từng service trong
# `var.services`, override rule mặc định với priority thấp hơn (match
# trước). Rule "Default" ẩn của AWS vẫn tồn tại làm fallback cho các
# service chưa khai báo.
#
# Usage:
#   module "xray" {
#     source         = "../../modules/observability/xray"
#     project_name   = "obs"
#     environment    = "lab"
#     services       = ["order-service", "payment-service"]
#     reservoir_size = 1
#     fixed_rate     = 0.3
#   }
#--------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
