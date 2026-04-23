# Terraform Policy — OPA / Conftest

Security & compliance policies viết bằng **Rego** (ngôn ngữ của Open Policy Agent).

## Quick Start

```bash
# 1. Cài conftest
curl -sL https://github.com/open-policy-agent/conftest/releases/download/v0.50.0/conftest_0.50.0_Linux_x86_64.tar.gz \
  | tar xz -C /usr/local/bin conftest

# 2. Tạo plan JSON
cd terraform/environments/shared
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json

# 3. Chạy policy check
conftest test tfplan.json --policy ../../policy/

# 4. Xem output chi tiết
conftest test tfplan.json --policy ../../policy/ --output table
conftest test tfplan.json --policy ../../policy/ --output table --all-namespaces

# 5. Output JSON cho CI/CD dashboards
conftest test tfplan.json --policy ../../policy/ --output json

# 6. Fail on warnings (dùng cho production)
conftest test tfplan.json --policy ../../policy/ --fail-on-warn
```

## Policy Files

| File | deny | warn | Level | Kiểm tra gì |
|------|------|------|-------|-------------|
| `rds.rego` | 4 | 3 | CRITICAL | Encryption, public access, IAM auth, backup >= 7d |
| `s3.rego` | 2 | 1 | CRITICAL | Public access block, encryption, versioning |
| `kms.rego` | 1 | 1 | SECURITY | Key rotation, deletion window |
| `general.rego` | 2 | 1 | COMPLIANCE | Tagging, cost guard, naming |
| `iam.rego` | 3 | 1 | SECURITY | Wildcard actions, trust policy, admin access |
| `security_group.rego` | 2 | 1 | NETWORK | Open ingress, SSH from 0.0.0.0/0, broad egress |
| `secrets.rego` | 1 | 1 | SECURITY | CMK encryption, recovery window |
| `logging.rego` | 1 | 1 | COMPLIANCE | Log encryption, retention |
| `network.rego` | 1 | 1 | NETWORK | VPC DNS, flow logs |
| `vpc_endpoint.rego` | 0 | 1 | NETWORK | Private DNS |

## Rego v1 Syntax — Cheat Sheet

```rego
# Package = nhóm policies
package terraform.rds

import rego.v1

# deny = hard rule → FAIL nếu match (Rego v1 syntax)
deny contains msg if {
    <tất cả dòng ở đây là AND>
    msg := "error message"
}

# warn = soft rule → PASS nhưng có warning
warn contains msg if {
    <điều kiện>
    msg := "warning message"
}

# Các operator:
#   ==              equals
#   !=              not equals
#   not X           negation
#   some x in coll  iterate (for-each)
#   :=              assign
#   sprintf()       format string
#   object.get()    null-safe field access
#   startswith()    string prefix check
```

## Cách đọc plan.json

```bash
# Xem structure:
cat tfplan.json | jq '.resource_changes[0]'

# Output:
# {
#   "address": "module.database.aws_db_instance.postgres",
#   "type": "aws_db_instance",
#   "mode": "managed",
#   "change": {
#     "actions": ["create"],
#     "after": {
#       "storage_encrypted": true,        ← policy check field này
#       "publicly_accessible": false,     ← và field này
#       "instance_class": "db.t3.micro",
#       ...
#     }
#   }
# }
```

## Running Tests

```bash
# Chạy tất cả policy unit tests
opa test policy/ policy/tests/ -v

# Chạy test cho 1 package
opa test policy/ policy/tests/rds_test.rego -v
```

## CI/CD Integration

Policy check tự động chạy trong GitHub Actions workflow `terraform-policy.yml`:
- **PR**: chạy `conftest test` với `--output table`
- **Production**: thêm `--fail-on-warn` để block cả warnings

## Ví dụ Output

```
$ conftest test tfplan.json --policy ../../policy/ --output table

+---------+----------------------------------+---------------------------------------------+
| RESULT  | FILE                             | MESSAGE                                     |
+---------+----------------------------------+---------------------------------------------+
| success | tfplan.json                      | 15 tests passed                             |
| warning | tfplan.json                      | 🟡 RDS nên bật multi_az cho production      |
| warning | tfplan.json                      | 🟡 RDS nên bật deletion_protection          |
| failure | tfplan.json                      | 🔴 Resource thiếu required tag 'Component'  |
+---------+----------------------------------+---------------------------------------------+
```
