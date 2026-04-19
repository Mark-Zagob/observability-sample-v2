#--------------------------------------------------------------
# VPC Endpoints Module — Gateway Endpoints (S3, DynamoDB)
#--------------------------------------------------------------
# Gateway Endpoints are FREE and add route entries to
# specified route tables. Traffic to S3/DynamoDB stays on
# AWS backbone — never touches NAT Gateway or Internet.
#
# Benefits:
#   - Zero cost (no hourly charge, no data processing)
#   - Reduces NAT Gateway data transfer costs
#   - Keeps traffic private (never leaves AWS network)
#   - Optional IAM policy for access restriction
#
# Reference: AWS Well-Architected COST06-BP01, SEC05-BP02
#--------------------------------------------------------------

# Auto-detect region instead of requiring variable
data "aws_region" "current" {}

#--------------------------------------------------------------
# S3 Gateway Endpoint
#--------------------------------------------------------------
# Used by: ECS (container image layers cached in S3),
#          CloudWatch Logs (backed by S3), Terraform state,
#          Application file uploads/downloads.
#--------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  # Optional: restrict which S3 buckets can be accessed from VPC
  # If not set, AWS default policy allows full S3 access
  policy = var.s3_endpoint_policy != "" ? var.s3_endpoint_policy : null

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-s3"
    Type = "gateway"
  })
}

#--------------------------------------------------------------
# DynamoDB Gateway Endpoint
#--------------------------------------------------------------
# Used by: Terraform state locking (DynamoDB table),
#          Application data access, DAX caching.
#--------------------------------------------------------------

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_dynamodb_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpce-dynamodb"
    Type = "gateway"
  })
}
