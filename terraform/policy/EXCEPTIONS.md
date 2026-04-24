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
| Network/SG | 0 | 0 | 3 | 3 |
| **Total** | **8** | **4** | **3** | **15** |

---

## FIX — Sẽ sửa trong code

### PE-001: CKV2_AWS_60 — Read Replica copy tags to snapshots

| Field | Value |
|-------|-------|
| Rule | Ensure RDS instance with copy tags to snapshots is enabled |
| Resource | `aws_db_instance.read_replica` |
| File | `rds.tf:172-221` |
| Decision | **FIX** |
| Action | Thêm `copy_tags_to_snapshot = true` vào read replica |

### PE-002: CKV2_AWS_69 — RDS encryption in transit

| Field | Value |
|-------|-------|
| Rule | Ensure AWS RDS instance configured with encryption in transit |
| Resource | `aws_db_instance.postgres`, `aws_db_instance.read_replica` |
| File | `rds.tf` |
| Decision | **FIX** |
| Action | Thêm `ca_cert_identifier` + enforce SSL trong parameter group (`rds.force_ssl = 1`) |

### PE-003: CKV2_AWS_34 — SSM Parameters encrypted

| Field | Value |
|-------|-------|
| Rule | Ensure AWS SSM Parameter is Encrypted |
| Resource | 6 SSM parameters trong `parameters.tf` |
| Decision | **FIX** |
| Action | Đổi `type = "String"` → `type = "SecureString"` + `key_id = aws_kms_key.rds.arn` |
| Note | Chỉ `db_secret_arn` chứa sensitive data, nhưng encrypt tất cả cho consistency |

---

## SKIP — Không fix, có justification

### PE-010: CKV_AWS_338 — Log retention < 365 ngày

| Field | Value |
|-------|-------|
| Rule | Ensure CloudWatch log groups retain logs for at least 1 year |
| Resource | `aws_cloudwatch_log_group.rds_postgres` |
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
- Checkov không phân biệt environment

**Compensating Control:**
- OPA policy enforce deletion_protection cho production
- Variable `deletion_protection` sẵn sàng bật khi cần

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

File `.checkov.yml` tại `terraform/modules/database/`:

```yaml
# .checkov.yml
compact: true
quiet: true
framework: terraform
skip-check:
  # Test fixtures — not production code
  - CKV_AWS_382    # PE-020: SG egress in test setup
  - CKV2_AWS_5     # PE-021: SG attachment in test setup
  - CKV2_AWS_12    # PE-022: VPC default SG in test
  - CKV2_AWS_11    # PE-022: VPC flow logs in test
  # Environment-aware — handled by OPA policies
  - CKV_AWS_157    # PE-012: Multi-AZ (OPA env-aware)
  - CKV_AWS_293    # PE-013: Deletion Protection (OPA env-aware)
  # False positive
  - CKV_AWS_118    # PE-011: Enhanced Monitoring (var not evaluated)
  # Retention — managed by OPA
  - CKV_AWS_338    # PE-010: Log retention (OPA enforce 30d min)
```
