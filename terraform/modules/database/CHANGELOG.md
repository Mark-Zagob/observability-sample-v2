# Changelog

All notable changes to the **Database Module** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-04-21

### Added
- **RDS PostgreSQL 16** instance with production-grade configuration:
  - `gp3` storage with autoscaling (`allocated_storage` → `max_allocated_storage`)
  - `storage_encrypted = true` (AWS managed KMS key)
  - `iam_database_authentication_enabled = true`
  - `performance_insights_enabled = true`
  - CloudWatch log exports for `postgresql` logs
  - Configurable Multi-AZ, backup retention, deletion protection
  - Maintenance and backup windows set to off-peak hours
- **Custom Parameter Group** (`postgres16` family):
  - `log_min_duration_statement = 1000` (log queries > 1s)
  - `log_statement = ddl` (log schema changes)
  - `log_disconnections = 1` (debug connection issues)
  - `shared_buffers = {DBInstanceClassMemory/4}` (auto-tuned to instance size)
- **Secrets Manager** for master password:
  - `random_password` (24 chars) — password never in tfvars
  - JSON secret with full connection metadata (username, password, host, port, dbname, url)
  - Recovery window: 0 days (lab) / 30 days (prod)
- **SSM Parameter Store** for endpoint discovery:
  - 6 parameters: endpoint, host, port, name, username, secret-arn
  - Hierarchy: `/{project}/{env}/database/*`
- **CloudWatch Monitoring**:
  - Log Group for RDS PostgreSQL logs (14-day retention lab, 90-day prod)
  - CPU High alarm (> 80%, 3 evaluation periods)
  - Storage Low alarm (< 2 GB)
  - Connections High alarm (> 70 connections for db.t3.micro)
- **Enhanced Monitoring** (conditional):
  - IAM role created only when `enhanced_monitoring_interval > 0`
  - Attached `AmazonRDSEnhancedMonitoringRole` managed policy
- **Contract tests** (`tests/contract.tftest.hcl`):
  - Variable validation tests (environment, backup_retention, monitoring_interval)
  - Default value verification
  - Subnet count validation

### Security
- Password auto-generated, stored in Secrets Manager, never in state file values
- Storage encrypted at-rest with KMS
- IAM database authentication enabled
- Instance placed in private data subnets only (`publicly_accessible = false`)
- Security Group enforced via `data_security_group_id` from security module

### Infrastructure
- Provider version pinned: `hashicorp/aws ~> 5.0`, `hashicorp/random ~> 3.0`
- Terraform `>= 1.5.0` required
- Input validation on `environment`, `backup_retention_period`, `enhanced_monitoring_interval`, `data_subnet_ids`
- `create_before_destroy` lifecycle on parameter group
- `ignore_changes` on password to prevent regeneration on apply
