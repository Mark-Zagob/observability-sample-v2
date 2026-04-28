# Policy Exceptions Register

> Tài liệu này ghi nhận tất cả security policy checks được **skip có chủ đích**,
> kèm justification và compensating controls.
>
> **Review cycle:** Mỗi 6 tháng hoặc khi thay đổi compliance requirements.

## Phân loại Decision

| Decision | Ý nghĩa |
|----------|---------|
| **FIX** | Sẽ fix trong code |
| **SKIP** | Không fix, có lý do hợp lệ |
| **SKIP (TEST ONLY)** | Fail trong test fixtures, không phải production code |

---

## Summary

| Category | Fix | Skip | Skip (Test) | Total |
|----------|-----|------|-------------|-------|
| RDS | 2 | 3 | 0 | 5 |
| SSM | 6 | 0 | 0 | 6 |
| Log Retention | 0 | 1 | 0 | 1 |
| Network/SG | 1 | 1 | 3 | 5 |
| Backup/S3 | 0 | 7 | 0 | 7 |
| **Total** | **9** | **12** | **3** | **24** |

---

## FIX — Sẽ sửa trong code

### PE-001: CKV2_AWS_60 — Read Replica copy tags to snapshots

| Field | Value |
|-------|-------|
| Rule | Ensure RDS instance with copy tags to snapshots is enabled |
| Resource | `aws_db_instance.read_replica` |
| File | `rds.tf:172-221` |
| Decision | **FIX** ✅ |
| Action | Thêm `copy_tags_to_snapshot = true` vào read replica |

### PE-002: CKV2_AWS_69 — RDS encryption in transit

| Field | Value |
|-------|-------|
| Rule | Ensure AWS RDS instance configured with encryption in transit |
| Resource | `aws_db_instance.postgres`, `aws_db_instance.read_replica` |
| File | `rds.tf` |
| Decision | **FIX** ✅ |
| Action | Enforce SSL trong parameter group (`rds.force_ssl = 1`) |

### PE-003: CKV2_AWS_34 — SSM Parameters encrypted

| Field | Value |
|-------|-------|
| Rule | Ensure AWS SSM Parameter is Encrypted |
| Resource | 6 SSM parameters trong `parameters.tf` |
| Decision | **FIX** ✅ |
| Action | Đổi `type = "String"` → `type = "SecureString"` + `key_id = aws_kms_key.rds.arn` |

### PE-031: CKV2_AWS_12 — VPC Default Security Group

| Field | Value |
|-------|-------|
| Rule | Ensure the default security group of every VPC restricts all traffic |
| Resource | `aws_vpc.this` |
| File | `network/vpc.tf` |
| Decision | **FIX** ✅ |
| Action | Thêm `aws_default_security_group` lockdown (deny all ingress/egress) |

---

## SKIP — Không fix, có justification

### PE-010: CKV_AWS_338 — Log retention < 365 ngày

| Field | Value |
|-------|-------|
| Rule | Ensure CloudWatch log groups retain logs for at least 1 year |
| Resource | `aws_cloudwatch_log_group.rds_postgres`, `aws_cloudwatch_log_group.flow_logs` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-24 |
| Review | 2026-10-24 |

**Justification:**
- Project không thuộc regulated industry (PCI-DSS, HIPAA)
- Retention enforce qua OPA policy: prod=90d, non-prod=30d
- Chi phí 365d cho mọi log group không cần thiết ở lab

**Compensating Control:**
- OPA `logging.rego` enforce minimum 30 ngày
- Nếu cần forensics > 90d → export S3 Glacier

### PE-011: CKV_AWS_118 — Enhanced Monitoring

| Field | Value |
|-------|-------|
| Rule | Ensure enhanced monitoring is enabled for RDS |
| Resource | `aws_db_instance.postgres` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-24 |
| Review | 2026-10-24 |

**Justification:**
- Checkov không detect dynamic value `var.enhanced_monitoring_interval`
- Code ĐÃ có: `monitoring_interval = var.enhanced_monitoring_interval` (default=60)
- Đây là **false positive** do Checkov không evaluate variables

**Compensating Control:**
- Biến `enhanced_monitoring_interval` default = 60 (bật sẵn)

### PE-012: CKV_AWS_157 — Multi-AZ

| Field | Value |
|-------|-------|
| Rule | Ensure RDS instances have Multi-AZ enabled |
| Resource | `aws_db_instance.postgres` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-24 |
| Review | 2026-10-24 |

**Justification:**
- Multi-AZ = +$30-50/month — không cần thiết cho lab/dev
- Đã có OPA `rds.rego` environment-aware: prod → DENY, dev → WARN
- Checkov không phân biệt environment

**Compensating Control:**
- OPA policy enforce multi_az cho production (`helpers.is_strict`)
- Variable `multi_az` sẵn sàng bật khi cần

### PE-013: CKV_AWS_293 — Deletion Protection

| Field | Value |
|-------|-------|
| Rule | Ensure database instances have deletion protection enabled |
| Resource | `aws_db_instance.postgres` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-24 |
| Review | 2026-10-24 |

**Justification:**
- Deletion protection gây khó khăn khi `terraform destroy` lab environment
- Đã có OPA `rds.rego` environment-aware: prod → DENY, dev → WARN

**Compensating Control:**
- OPA policy enforce deletion_protection cho production
- Variable `deletion_protection` sẵn sàng bật khi cần

### PE-030: CKV_AWS_130 — Public Subnet auto-assign public IP

| Field | Value |
|-------|-------|
| Rule | Ensure VPC subnets do not assign public IP by default |
| Resource | `aws_subnet.public` |
| File | `network/subnets.tf` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-24 |
| Review | 2026-10-24 |

**Justification:**
- Public subnet **cần** public IP cho NAT Gateway và ALB
- Private/data subnets đã có `map_public_ip_on_launch = false`
- **False positive** — Checkov không phân biệt subnet tier

**Compensating Control:**
- 3-tier subnet architecture: public / private / data
- Services (ECS, RDS) deploy vào private/data subnet, KHÔNG vào public

### PE-040 → PE-044: CKV_AWS_145, CKV_AWS_21, CKV2_AWS_6, CKV2_AWS_61, CKV_AWS_18 — S3 Backup Reports (False Positives)

| Field | Value |
|-------|-------|
| Rule | S3 bucket encryption, versioning, public access block, lifecycle, access logging |
| Resource | `aws_s3_bucket.backup_reports` |
| File | `backup/reporting.tf` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-28 |
| Review | 2026-10-28 |

**Justification:**
- Tất cả 5 controls **ĐÃ implement** qua separate Terraform resources:
  - `aws_s3_bucket_server_side_encryption_configuration.backup_reports` (KMS)
  - `aws_s3_bucket_versioning.backup_reports` (Versioning)
  - `aws_s3_bucket_public_access_block.backup_reports` (Public block)
  - `aws_s3_bucket_lifecycle_configuration.backup_reports` (Lifecycle)
  - `aws_s3_bucket_logging.backup_reports` (Access logging)
- **False positive** — Checkov cannot correlate `aws_s3_bucket_*` resources with `count`

**Compensating Control:**
- OPA `backup.rego` Rule #6-7 enforce public access block + KMS encryption
- Bucket policy enforces TLS + deny unencrypted uploads

### PE-045: CKV_AWS_144 — S3 Cross-Region Replication

| Field | Value |
|-------|-------|
| Rule | Ensure S3 bucket has cross-region replication enabled |
| Resource | `aws_s3_bucket.backup_reports` |
| File | `backup/reporting.tf` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-28 |
| Review | 2026-10-28 |

**Justification:**
- Report bucket chứa CSV compliance reports — **có thể regenerate**
- Actual backup data ĐÃ cross-region copy qua AWS Backup `copy_action`
- CRR cho report bucket = chi phí không cần thiết

**Compensating Control:**
- AWS Backup cross-region copy bảo vệ actual backup data
- Report plan tự generate daily — mất data cũ chỉ cần re-run

### PE-046: CKV2_AWS_62 — S3 Event Notifications

| Field | Value |
|-------|-------|
| Rule | Ensure S3 buckets should have event notifications enabled |
| Resource | `aws_s3_bucket.backup_reports` |
| File | `backup/reporting.tf` |
| Decision | **SKIP** |
| Owner | @mark |
| Date | 2026-04-28 |
| Review | 2026-10-28 |

**Justification:**
- Report bucket nhận CSV từ AWS Backup service — không cần event notifications
- Backup job failures được monitor qua SNS + CloudWatch alarms (separate channel)

**Compensating Control:**
- `aws_backup_vault_notifications` → SNS events cho BACKUP_JOB_FAILED
- `aws_cloudwatch_metric_alarm.backup_job_failed` → alarm cho backup failures

---

## SKIP (TEST ONLY) — Fail trong test fixtures

Các checks sau fail trong `tests/setup/main.tf` — đây là **test fixtures**,
không phải production infrastructure code.

### PE-020: CKV_AWS_382 — Security Group egress 0.0.0.0/0

| Field | Value |
|-------|-------|
| Resource | `aws_security_group.data` in `tests/setup/main.tf` |
| Decision | **SKIP (TEST ONLY)** |
| Justification | Test fixture SG, không deploy production |

### PE-021: CKV2_AWS_5 — Security Group not attached

| Field | Value |
|-------|-------|
| Resource | `aws_security_group.data` in `tests/setup/main.tf` |
| Decision | **SKIP (TEST ONLY)** |
| Justification | SG attached trong test config, Checkov không detect cross-file |

### PE-022: CKV2_AWS_12 + CKV2_AWS_11 — VPC default SG + flow logs

| Field | Value |
|-------|-------|
| Resource | `aws_vpc.test` in `tests/setup/main.tf` |
| Decision | **SKIP (TEST ONLY)** |
| Justification | Test VPC, minimal config by design |

---

## Checkov Config

### Database Module — `terraform/modules/database/.checkov.yml`

```yaml
skip-check:
  - CKV_AWS_382    # PE-020: SG egress in test setup
  - CKV2_AWS_5     # PE-021: SG attachment in test setup
  - CKV2_AWS_12    # PE-022: VPC default SG in test
  - CKV2_AWS_11    # PE-022: VPC flow logs in test
  - CKV_AWS_157    # PE-012: Multi-AZ (OPA env-aware)
  - CKV_AWS_293    # PE-013: Deletion Protection (OPA env-aware)
  - CKV_AWS_118    # PE-011: Enhanced Monitoring (false positive)
  - CKV_AWS_338    # PE-010: Log retention (OPA enforce 30d min)
```

### Network Module — `terraform/modules/network/.checkov.yml`

```yaml
skip-check:
  - CKV_AWS_130    # PE-030: Public subnets need public IPs
  - CKV_AWS_338    # PE-010: Log retention (OPA enforce 30d min)
```

### Backup Module — `terraform/modules/backup/.checkov.yml`

```yaml
skip-check:
  - CKV_AWS_145    # PE-040: KMS → separate resource
  - CKV_AWS_21     # PE-041: Versioning → separate resource
  - CKV2_AWS_6     # PE-042: Public access block → separate resource
  - CKV2_AWS_61    # PE-043: Lifecycle → separate resource
  - CKV_AWS_18     # PE-044: Access logging → separate resource
  - CKV_AWS_144    # PE-045: CRR not needed (reports regenerable)
  - CKV2_AWS_62    # PE-046: Event notifications not needed
```
