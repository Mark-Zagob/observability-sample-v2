#--------------------------------------------------------------
# Shared Environment - Backend Configuration
#--------------------------------------------------------------
# Hiện tại dùng LOCAL state (file terraform.tfstate tại folder này)
# Khi chuyển production, uncomment block bên dưới để dùng S3 + DynamoDB

# terraform {
#   backend "s3" {
#     bucket         = "observability-lab-tfstate"
#     key            = "shared/terraform.tfstate"
#     region         = "ap-southeast-2"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
