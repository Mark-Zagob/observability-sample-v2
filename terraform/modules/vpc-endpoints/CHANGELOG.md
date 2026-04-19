# Changelog

All notable changes to the **VPC Endpoints Module** will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [1.0.0] - 2026-04-19

### Added
- **Gateway Endpoints**: S3 + DynamoDB with individual enable/disable toggles (FREE)
- **Interface Endpoints**: 7 default services (ECR, CW Logs, SSM, Secrets Manager, STS, Monitoring) with `for_each`
- **Security Group**: `name_prefix` + `create_before_destroy` pattern, HTTPS-only ingress from VPC CIDR
- **S3 Endpoint Policy**: Optional custom IAM policy to restrict S3 bucket access
- **Prefix List Outputs**: `s3_endpoint_prefix_list_id` for SG-based S3 egress restriction
- **DNS Outputs**: `interface_endpoint_dns` map for service discovery
- **Audit Outputs**: `all_endpoint_ids` flat list, `gateway_endpoints` map
- **Region auto-detect**: `data.aws_region.current` instead of `var.aws_region`
- **Provider constraints**: `~> 5.0` (pessimistic)
- **Contract tests**: 8 plan-only tests (variable validation, toggle behavior)
- **Integration tests**: 7 apply+destroy tests (gateway, interface, tags, audit)
- **Test helper**: Minimal VPC + subnet + route table (`tests/setup/`)

### Changed (from scaffold)
- Split monolithic `main.tf` into `gateway_endpoints.tf` + `interface_endpoints.tf`
- Replaced `aws_vpc_security_group_*_rule` with `aws_security_group_rule` (consistent with security module)
- Removed overly-permissive egress rule on endpoint SG (endpoints don't need egress)
- Changed SG from `name` to `name_prefix` for safe replacement
- Removed `var.aws_region` dependency (uses data source)
- Changed disabled outputs from `null` to `""` (consistent with security module)
