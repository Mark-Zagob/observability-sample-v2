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
```

## Policy Files

| File | Rules | Level | Kiểm tra gì |
|------|-------|-------|-------------|
| `rds.rego` | 4 deny, 3 warn | CRITICAL | Encryption, public access, IAM auth, backup |
| `s3.rego` | 2 deny, 1 warn | CRITICAL | Public access block, encryption, versioning |
| `kms.rego` | 1 deny, 1 warn | SECURITY | Key rotation, deletion window |
| `general.rego` | 2 deny, 1 warn | COMPLIANCE | Tagging, cost guard, naming |

## Rego Syntax — Cheat Sheet

```rego
# Package = nhóm policies
package terraform.rds

# deny = hard rule → FAIL nếu match
deny[msg] {
    <tất cả dòng ở đây là AND>
    msg := "error message"
}

# warn = soft rule → PASS nhưng có warning
warn[msg] {
    <điều kiện>
    msg := "warning message"
}

# Các operator:
#   ==        equals
#   !=        not equals
#   not X     negation
#   X[_]      iterate (for-each)
#   some x    declare local variable
#   :=        assign
#   sprintf() format string
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
