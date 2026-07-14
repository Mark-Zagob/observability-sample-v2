# VPC Endpoints Module

Production-grade AWS VPC Endpoints for keeping traffic on the AWS backbone. Eliminates NAT Gateway data transfer costs for AWS service calls and improves security by preventing traffic from traversing the public Internet.

## Architecture

```
Private Subnets                         AWS Services
┌─────────────────┐                    ┌──────────────┐
│  ECS Tasks      │──── Gateway ────── │  S3          │  FREE
│  Terraform      │──── Gateway ────── │  DynamoDB    │  FREE
│                 │                    │              │
│  ECS Agent      │──── Interface ──── │  ECR         │  $7.2/mo/AZ
│  App Logs       │──── Interface ──── │  CW Logs     │  $7.2/mo/AZ
│  Secrets        │──── Interface ──── │  SSM + SM    │  $7.2/mo/AZ
│  IAM Auth       │──── Interface ──── │  STS         │  $7.2/mo/AZ
│  Metrics        │──── Interface ──── │  CW Metrics  │  $7.2/mo/AZ
└─────────────────┘                    └──────────────┘
         │                                     │
         └─── Private DNS resolves to ─────────┘
              private IPs (no NAT needed)
```

**Key benefits:**
- **Cost savings**: S3/DynamoDB Gateway Endpoints are FREE. Traffic avoids NAT GW ($0.045/GB).
- **Performance**: Traffic stays on AWS backbone — lower latency, higher throughput.
- **Security**: No Internet exposure. ECR pulls, log writes, and secret reads never leave VPC.

## Usage

```hcl
module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  project_name = "my-project"
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr_block

  # All route tables for Gateway Endpoints
  route_table_ids = concat(
    [module.network.public_route_table_id],
    values(module.network.private_route_table_ids),
    values(module.network.mgmt_route_table_ids),
    [module.network.data_route_table_id]
  )

  # Interface Endpoints (disable for dev/lab to save cost)
  enable_interface_endpoints = true
  private_subnet_ids         = module.network.private_subnet_ids

  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `project_name` | `string` | — | ✅ | Project name (lowercase, digits, hyphens) |
| `vpc_id` | `string` | — | ✅ | VPC ID (validated: `vpc-*`) |
| `vpc_cidr` | `string` | — | ✅ | VPC CIDR for SG ingress rules |
| `route_table_ids` | `list(string)` | — | ✅ | Route tables for Gateway Endpoints |
| `private_subnet_ids` | `list(string)` | `[]` | no | Subnets for Interface Endpoint ENIs |
| `enable_s3_endpoint` | `bool` | `true` | no | S3 Gateway Endpoint (FREE) |
| `enable_dynamodb_endpoint` | `bool` | `true` | no | DynamoDB Gateway Endpoint (FREE) |
| `enable_interface_endpoints` | `bool` | `false` | no | Interface Endpoints (~$7.2/mo/AZ each) |
| `interface_endpoint_services` | `list(string)` | 7 services | no | AWS services for Interface Endpoints |
| `s3_endpoint_policy` | `string` | `""` | no | Custom IAM policy for S3 endpoint |
| `common_tags` | `map(string)` | `{}` | no | Tags applied to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `s3_endpoint_id` | S3 Gateway Endpoint ID |
| `s3_endpoint_prefix_list_id` | Prefix list ID for SG-based S3 egress restriction |
| `dynamodb_endpoint_id` | DynamoDB Gateway Endpoint ID |
| `dynamodb_endpoint_prefix_list_id` | DynamoDB prefix list ID |
| `interface_endpoint_ids` | Map of service → Endpoint ID |
| `interface_endpoint_dns` | Map of service → private DNS name |
| `endpoints_security_group_id` | SG ID (empty if Interface disabled) |
| `gateway_endpoints` | Map of gateway endpoint names → IDs |
| `all_endpoint_ids` | Flat list of ALL endpoint IDs (for audit) |

## File Structure

```
vpc-endpoints/
├── gateway_endpoints.tf      # S3 + DynamoDB (FREE)
├── interface_endpoints.tf    # SG + Interface Endpoints (paid) + precondition
├── variables.tf              # Input variables with validation
├── outputs.tf                # Module outputs (IDs, DNS, maps)
├── versions.tf               # Provider constraints (~> 5.0)
├── CHANGELOG.md              # Release history
└── tests/
    ├── setup/
    │   └── main.tf                  # Helper: VPC + subnet + route table
    ├── contract.tftest.hcl          # 8 plan-only tests
    └── integration.tftest.hcl       # 7 apply+destroy tests
```

## Testing

### Contract Tests (Plan Only — $0, ~10s)

```bash
cd terraform/modules/vpc-endpoints
terraform init
terraform test -filter=tests/contract.tftest.hcl
```

### Integration Tests (Apply + Destroy — ~$0.05, ~5min)

```bash
terraform test -filter=tests/integration.tftest.hcl
```

| # | Test | What It Validates |
|---|------|-------------------|
| 0 | `setup_vpc` | Helper VPC + subnet + route table |
| 1 | `s3_gateway_endpoint_created` | S3 endpoint + prefix list ID |
| 2 | `dynamodb_gateway_endpoint_created` | DynamoDB endpoint + prefix list |
| 3 | `gateway_endpoints_map_correct` | Map has s3 + dynamodb keys |
| 4 | `s3_disabled_output_empty` | S3 toggle OFF → empty string |
| 5 | `interface_endpoints_created` | SG + SSM/STS endpoints |
| 6 | `tags_applied_to_endpoints` | Type, Service, Tier, common_tags |
| 7 | `all_endpoint_ids_complete` | Audit: 4 total (2 gw + 2 iface) |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate module from network | Independent lifecycle — endpoints can change without VPC recreation |
| `data.aws_region` over `var.aws_region` | Auto-detect — eliminates region mismatch bugs |
| Gateway endpoints always recommended | FREE, zero downside — saves NAT data transfer costs |
| Interface endpoints OFF by default | ~$7.2/month/AZ per endpoint — opt-in for production |
| Single SG for all interface endpoints | All endpoints speak HTTPS on 443 — shared SG is correct |
| No egress rule on endpoint SG | Endpoints are service-side — they don't initiate connections |
| `for_each` on services | Adding/removing services doesn't recreate existing endpoints |
| `prefix_list_id` outputs | Enables SG rules like "allow egress to S3 only" without CIDRs |
| Custom S3 endpoint policy | Restrict which S3 buckets are accessible from VPC |

## Cost Considerations

| Resource | Dev/Lab | Production (2 AZ) | Production (3 AZ) |
|----------|---------|--------------------|--------------------|
| S3 Gateway | FREE | FREE | FREE |
| DynamoDB Gateway | FREE | FREE | FREE |
| Interface (7 svc) | $0 (disabled) | ~$100.80/mo | ~$151.20/mo |
| NAT savings | — | ~$50-200/mo saved | ~$75-300/mo saved |

> **ROI:** Interface Endpoints typically pay for themselves by reducing NAT Gateway data transfer costs, especially for ECR image pulls and CloudWatch log writes.

## Related Modules

- [`network`](../network/) — Provides VPC ID, CIDR, route table IDs, subnet IDs
- [`security`](../security/) — Can use `s3_endpoint_prefix_list_id` to restrict App SG egress to S3 only
