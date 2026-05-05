# Changelog

All notable changes to the **Logging Module** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-05

### Added
- **S3 Bucket** for VPC Flow Logs long-term archive (`s3.tf`):
  - SSE-KMS encryption with dedicated CMK (bucket key enabled)
  - Versioning enabled for accidental delete protection
  - Public access blocked (all 4 settings)
  - Bucket policy: `delivery.logs.amazonaws.com` write access
  - Enforce TLS (deny unencrypted transport)
  - Lifecycle: Standard → Glacier Flexible Retrieval → Delete
  - Noncurrent version cleanup after 30 days
- **KMS CMK** for S3 bucket encryption (`kms.tf`):
  - Separate from CloudWatch Flow Logs key (defense-in-depth)
  - Auto-rotation enabled
  - Key policy grants `delivery.logs.amazonaws.com` encrypt access
  - `aws:SourceAccount` condition for cross-account protection
- **Athena / Glue Catalog** for SQL queries (`athena.tf`):
  - Glue database + table with VPC Flow Logs v2 schema (14 columns)
  - Partition projection (date/region/account_id) — no crawlers needed
  - Athena workgroup with encrypted query results (SSE-KMS)
  - Enforced workgroup configuration
- **Variables** with validation:
  - `flow_logs_glacier_transition_days` (min 30, default 90)
  - `flow_logs_expiration_days` (min 90, default 365)
  - `athena_query_result_retention_days` (default 7)

### Security
- Dedicated CMK per log store (defense-in-depth)
- S3 public access fully blocked (CIS AWS 2.1.2)
- TLS enforced on all S3 operations (CIS AWS 2.1.1)
- KMS key policy scoped to source account
- Athena query results encrypted at rest

### Design Decisions
- **Separate module from network** — log storage lifecycle differs from VPC
  lifecycle. Destroying VPC must not destroy log archive.
- **Partition projection** — eliminates Glue crawler cost and MSCK REPAIR TABLE
  manual step. Athena queries work immediately after deploy.
- **Bucket key enabled** — reduces KMS API costs by ~99% for high-volume writes
