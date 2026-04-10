# VPC Endpoints Module

Standalone module for managing VPC Gateway and Interface Endpoints,
decoupled from the core network module for independent lifecycle management.

## Architecture

- **Gateway Endpoints** (S3, DynamoDB) — always created, free of charge
- **Interface Endpoints** — optional, toggled via `enable_interface_endpoints`
- **Security Group** — restricts Interface Endpoint access to HTTPS from VPC CIDR

## Usage

```hcl
module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  project_name = "observability"
  aws_region   = "ap-southeast-1"
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr_block

  # All route tables for Gateway Endpoints
  route_table_ids = concat(
    [module.network.public_route_table_id],
    values(module.network.private_route_table_ids),
    [module.network.data_route_table_id],
    values(module.network.mgmt_route_table_ids)
  )

  # Interface Endpoints (optional)
  enable_interface_endpoints = false
  private_subnet_ids         = module.network.private_subnet_ids

  common_tags = {
    Project     = "observability"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_name` | Project name for resource naming | `string` | — | yes |
| `aws_region` | AWS region for service names | `string` | — | yes |
| `vpc_id` | VPC ID | `string` | — | yes |
| `vpc_cidr` | VPC CIDR for SG ingress | `string` | — | yes |
| `route_table_ids` | Route table IDs for Gateway Endpoints | `list(string)` | — | yes |
| `private_subnet_ids` | Subnet IDs for Interface Endpoints | `list(string)` | `[]` | no |
| `enable_interface_endpoints` | Toggle Interface Endpoints | `bool` | `false` | no |
| `interface_endpoint_services` | AWS services for Interface Endpoints | `list(string)` | see variables.tf | no |
| `common_tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `s3_endpoint_id` | S3 Gateway Endpoint ID |
| `dynamodb_endpoint_id` | DynamoDB Gateway Endpoint ID |
| `interface_endpoint_ids` | Map of service → Endpoint ID |
| `endpoints_security_group_id` | SG ID (null if Interface Endpoints disabled) |
