# Changelog

All notable changes to the **Security Module** will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [1.0.2] - 2026-04-19

### Added
- **Contract tests**: 8 plan-only tests validating variable constraints (`project_name`, `vpc_id`, `app_port`, `allowed_ssh_cidrs`, `vpc_cidr_block`) and default values — zero cost, ~15s
- **Integration tests**: 9 apply+destroy tests covering SG creation, uniqueness, map output contract, IAM roles, bastion toggle (ON→OFF→ON), key pair generation, and tag propagation — ~$0.02, ~3min
- **Test helper**: Minimal VPC setup module (`tests/setup/`) for SG integration testing without depending on the network module

### Changed
- **README.md**: Added Testing, File Structure, Design Decisions, and Cost sections following network module pattern

## [1.0.1] - 2026-04-19

### Changed
- **Provider constraints**: Tightened from `>= 5.0` to `~> 5.0` (AWS), `>= 4.0` to `~> 4.0` (TLS), `>= 2.4` to `~> 2.4` (local) for production stability

## [1.0.0] - 2026-04-15

### Added
- **Security Groups**: Defense-in-depth SGs for 6 tiers (ALB, Application, Data, EFS, Observability, Bastion)
- **IAM Roles**: ECS Task Execution Role + ECS Task Role with least-privilege policies
- **IAM Bastion**: Bastion Instance Profile with SSM Session Manager support
- **Key Pair**: Dual-mode SSH key management (lab auto-generate / production import)
- **Variable validation**: Input validation for vpc_id, CIDR blocks, port ranges
- **Conditional resources**: Bastion resources toggled via `enable_bastion`
- **Output interface**: SG IDs, IAM ARNs, key pair name for downstream modules
