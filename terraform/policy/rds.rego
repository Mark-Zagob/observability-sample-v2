# =============================================================
# RDS Security Policies
# =============================================================
# Kiểm tra: encryption, public access, IAM auth, backup,
#           deletion protection, monitoring
#
# Environment-aware:
#   - Production/unknown: deletion_protection, multi_az = DENY
#   - Dev/staging: deletion_protection, multi_az = WARN
# =============================================================

package terraform.rds

import rego.v1

import data.terraform.helpers

# ----- DENY: Hard rules — vi phạm = BLOCK (mọi environment) -----

# Rule 1: RDS phải encrypted [CIS-AWS-2.3.1] [SOC2-CC6.1]
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.storage_encrypted != true
    msg := sprintf(
        "🔴 [CRITICAL][CIS-AWS-2.3.1] RDS '%s' phải bật storage encryption (storage_encrypted = true)",
        [rc.address]
    )
}

# Rule 2: RDS không được public [CIS-AWS-2.3.2] [SOC2-CC6.6]
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.publicly_accessible == true
    msg := sprintf(
        "🔴 [CRITICAL][CIS-AWS-2.3.2] RDS '%s' KHÔNG được publicly accessible",
        [rc.address]
    )
}

# Rule 3: RDS phải bật IAM authentication [SOC2-CC6.1]
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.iam_database_authentication_enabled != true
    msg := sprintf(
        "🔴 [SECURITY][SOC2-CC6.1] RDS '%s' phải bật IAM database authentication",
        [rc.address]
    )
}

# Rule 4: RDS primary phải có backup >= 7 ngày (compliance minimum)
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    retention := rc.change.after.backup_retention_period
    retention < 7
    msg := sprintf(
        "🔴 [DATA] RDS '%s' backup_retention_period = %d (phải >= 7 ngày cho compliance)",
        [rc.address, retention]
    )
}

# ----- DENY (Production only): Strict rules cho production -----

# Rule 5a: Production PHẢI có deletion protection
deny contains msg if {
    helpers.is_strict
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.deletion_protection != true
    msg := sprintf(
        "🔴 [PROD] RDS '%s' PHẢI bật deletion_protection trong production",
        [rc.address]
    )
}

# Rule 6a: Production PHẢI có Multi-AZ
deny contains msg if {
    helpers.is_strict
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.multi_az != true
    msg := sprintf(
        "🔴 [PROD] RDS '%s' PHẢI bật multi_az trong production (failover tự động)",
        [rc.address]
    )
}

# ----- WARN: Soft rules — cho dev/staging -----

# Rule 5b: Dev/staging NÊN có deletion protection
warn contains msg if {
    not helpers.is_strict
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.deletion_protection != true
    msg := sprintf(
        "🟡 [WARNING] RDS '%s' nên bật deletion_protection",
        [rc.address]
    )
}

# Rule 6b: Dev/staging NÊN có Multi-AZ
warn contains msg if {
    not helpers.is_strict
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.multi_az != true
    msg := sprintf(
        "🟡 [HA] RDS '%s' nên bật multi_az (failover tự động)",
        [rc.address]
    )
}

# Rule 7: Nên bật Performance Insights (mọi environment)
warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.performance_insights_enabled != true
    msg := sprintf(
        "🟡 [WARNING] RDS '%s' nên bật Performance Insights để debug slow queries",
        [rc.address]
    )
}
