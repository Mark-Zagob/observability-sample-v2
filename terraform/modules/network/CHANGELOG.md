# Changelog

All notable changes to the **Network Module** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-04-16

### Added
- Integration tests (`tests/integration.tftest.hcl`) — 10 apply+destroy tests
  covering VPC creation, AZ spread, CIDR uniqueness, NAT modes, route tables,
  flow logs, output contracts, and tag propagation

### Fixed
- Integration test ordering to avoid AWS EIP/ENI race condition during
  NAT Gateway scale-down between `run` blocks (shared state issue)
- Explicit `enable_flow_logs = false` for tests not requiring flow logs
  to prevent KMS/CloudWatch permission errors
- Explicit `single_nat_gateway` pinning in all tests to prevent
  unintended NAT state transitions

## [1.0.0] - 2026-04-16

### Added
- **VPC** with DNS support and hostnames enabled (`vpc.tf`)
- **4-tier subnet allocation** using `cidrsubnet()` from a single `/16` VPC CIDR:
  - Private: `/20` (4,094 IPs per AZ — sized for EKS pod density)
  - Public: `/24` (254 IPs per AZ — ALB, NAT Gateway)
  - Data: `/26` (62 IPs per AZ — RDS, ElastiCache)
  - Management: `/27` (30 IPs per AZ — Bastion, monitoring)
- **NAT Gateway** with two modes:
  - `single_nat_gateway = true` → 1 NAT (cost-saving, ~$32/month)
  - `single_nat_gateway = false` → 1 NAT per AZ (HA, ~$96/month for 3 AZs)
- **VPC Flow Logs** to CloudWatch with:
  - KMS CMK encryption (auto-rotation enabled)
  - Configurable retention period (default: 7 days)
  - Conditional creation via `enable_flow_logs` variable
- **Internet Gateway** for public subnet routing
- **Route tables** per tier:
  - Public → IGW (shared across AZs)
  - Private → NAT GW (per-AZ for fault isolation)
  - Data → local only (no internet access)
  - Management → NAT GW (per-AZ)
- **Network ACLs** — defense-in-depth rules for all 4 tiers (commented out,
  ready to uncomment per environment needs)
- **Tier tagging** — all subnets tagged with `Tier = public|private|data|mgmt`
- **Flexible AZ count** — supports 2 or 3 AZs via `az_count` variable
- **18 outputs** — VPC ID, subnet IDs/CIDRs, route table IDs, NAT IDs/IPs,
  AZ maps for downstream module consumption
- **16 contract tests** (`tests/network.tftest.hcl`) — plan-only validation of:
  - Subnet counts, CIDR prefix lengths, CIDR containment
  - NAT single/HA modes, flow log conditional creation
  - KMS encryption, key rotation, tier tags, output contracts, 2-AZ mode

### Security
- Flow Logs encrypted with dedicated KMS CMK (CIS AWS Benchmark 3.9)
- KMS automatic key rotation enabled (CIS Benchmark 2.8)
- Data subnets isolated — no internet route in route table
- NACL templates block SSH/RDP/DB ports from internet (defense-in-depth)

### Infrastructure
- All resources use `for_each` with AZ map for stable addressing
- Provider version pinned: `hashicorp/aws ~> 5.0`
- Input validation on `project_name`, `aws_region`, `vpc_cidr`, `az_count`,
  and `flow_logs_retention_days`
