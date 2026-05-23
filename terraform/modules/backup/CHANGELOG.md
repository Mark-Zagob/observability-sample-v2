# Changelog

All notable changes to the **Backup Module** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-04-28

### Added
- **Backup Report Plan** — daily compliance CSV reports to S3 (`reporting.tf`)
- **S3 Report Bucket** — KMS-encrypted, versioned, public access blocked, with lifecycle auto-expiry
- **Region Settings** — explicit `aws_backup_region_settings` opt-in for RDS, EFS, DynamoDB, EBS, S3
- **Variables:** `enable_backup_reports`, `backup_reports_retention_days`,
  `daily_start_window`, `daily_completion_window`, `monthly_start_window`, `monthly_completion_window`
- **Cold storage preconditions** — validates `retention >= cold_storage_after + 90` (AWS minimum)
- **OPA rules #6-8** — S3 public access block, KMS encryption, completion_window minimum
- **Integration test** — `tests/integration.tftest.hcl` (7 test runs with real AWS resources)

## [1.1.0] - 2026-04-28

### Fixed
- **DR KMS key missing policy** — AWS Backup service could not encrypt/decrypt
  recovery points in the DR vault, causing cross-region restore to fail
- **DR vault missing protections** — added vault lock + access policy (deny delete)
  matching primary vault's security posture
- **Stale comment** in `notifications.tf` — event names now match actual code

### Added
- **Retention validation** — `lifecycle.precondition` blocks in `plan.tf` catch
  `daily_retention_days > vault_lock_max_retention_days` at plan time
- **README.md** — module documentation (architecture, usage, inputs/outputs)
- **CHANGELOG.md** — this file
- **examples/basic/** — minimal and DR-enabled usage examples
- **tests/contract.tftest.hcl** — variable validation contract tests

## [1.0.0] - 2026-04-28

### Added
- **Backup Vault** (primary region):
  - KMS CMK encryption (separate from RDS key)
  - Vault lock (governance mode, configurable to compliance)
  - Access policy: deny `DeleteRecoveryPoint` except backup service role
- **Backup Vault** (DR region, conditional):
  - Cross-region copy destination (`ap-southeast-1`)
  - Dedicated KMS CMK with backup service policy
- **Backup Plan** with two rules:
  - Daily: 3 AM UTC, 35-day retention, optional cross-region copy
  - Monthly: 1st of month, 365-day retention, cold storage after 30 days
- **Tag-based Selection**: auto-discover resources with `Backup=true`
- **IAM Role** with 4 AWS managed policies (backup + restore + S3)
- **SNS Topic** (KMS encrypted) with vault event notifications
- **CloudWatch Alarms** for backup job + copy job failures
- **OPA Policy** (`policy/backup.rego`): 5 rules for vault encryption,
  vault lock, retention minimum, tag-based selection, SNS encryption

### Security
- All vaults encrypted with dedicated CMKs
- Vault access policy prevents backup deletion by compromised IAM users
- SNS topic encrypted with KMS
- IAM uses AWS managed policies (no wildcard custom policies)
