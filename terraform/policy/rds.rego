# =============================================================
# RDS Security Policies
# =============================================================
# Kiểm tra: encryption, public access, IAM auth, backup,
#           deletion protection, monitoring
#
# Rego v1 syntax (OPA v1 / Conftest v0.46+):
#   deny contains msg if { ... }   ← thay cho deny[msg] { ... }
# =============================================================

package terraform.rds

import rego.v1

# ----- DENY: Hard rules — vi phạm = BLOCK -----

# Rule 1: RDS phải encrypted
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.storage_encrypted != true
    msg := sprintf(
        "🔴 [CRITICAL] RDS '%s' phải bật storage encryption (storage_encrypted = true)",
        [rc.address]
    )
}

# Rule 2: RDS không được public
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.publicly_accessible == true
    msg := sprintf(
        "🔴 [CRITICAL] RDS '%s' KHÔNG được publicly accessible",
        [rc.address]
    )
}

# Rule 3: RDS phải bật IAM authentication
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    rc.change.after.iam_database_authentication_enabled != true
    msg := sprintf(
        "🔴 [SECURITY] RDS '%s' phải bật IAM database authentication",
        [rc.address]
    )
}

# Rule 4: RDS phải có backup (chỉ check primary, không check replica)
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.backup_retention_period == 0
    msg := sprintf(
        "🔴 [DATA] RDS '%s' phải có backup (backup_retention_period > 0)",
        [rc.address]
    )
}

# ----- WARN: Soft rules — cảnh báo nhưng không block -----

# Rule 5: Nên bật deletion protection
warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.deletion_protection != true
    msg := sprintf(
        "🟡 [WARNING] RDS '%s' nên bật deletion_protection cho production",
        [rc.address]
    )
}

# Rule 6: Nên bật Performance Insights
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

# Rule 7: Nên bật Multi-AZ cho production
warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    not rc.change.after.replicate_source_db
    rc.change.after.multi_az != true
    msg := sprintf(
        "🟡 [HA] RDS '%s' nên bật multi_az cho production (failover tự động)",
        [rc.address]
    )
}
