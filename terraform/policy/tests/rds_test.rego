# =============================================================
# RDS Policy Unit Tests
# =============================================================

package terraform.rds_test

import rego.v1

import data.terraform.rds

# --- Helper: base RDS resource change ---

base_rds_after := {
    "storage_encrypted": true,
    "publicly_accessible": false,
    "iam_database_authentication_enabled": true,
    "backup_retention_period": 7,
    "deletion_protection": true,
    "performance_insights_enabled": true,
    "multi_az": true,
    "tags_all": {"Environment": "dev", "Project": "obs", "ManagedBy": "terraform"},
}

make_rc(after_overrides) := {
    "address": "module.database.aws_db_instance.test",
    "type": "aws_db_instance",
    "mode": "managed",
    "change": {"actions": ["create"], "after": object.union(base_rds_after, after_overrides)},
}

make_input(rcs) := {"resource_changes": rcs}

# === DENY: storage_encrypted ===

test_deny_rds_no_encryption if {
    rc := make_rc({"storage_encrypted": false})
    count(rds.deny) > 0 with input as make_input([rc])
}

test_allow_rds_encrypted if {
    rc := make_rc({})
    count(rds.deny) == 0 with input as make_input([rc])
}

# === DENY: publicly_accessible ===

test_deny_rds_public if {
    rc := make_rc({"publicly_accessible": true})
    count(rds.deny) > 0 with input as make_input([rc])
}

# === DENY: iam_database_authentication_enabled ===

test_deny_rds_no_iam_auth if {
    rc := make_rc({"iam_database_authentication_enabled": false})
    count(rds.deny) > 0 with input as make_input([rc])
}

# === DENY: backup_retention_period < 7 ===

test_deny_rds_backup_zero if {
    rc := make_rc({"backup_retention_period": 0})
    count(rds.deny) > 0 with input as make_input([rc])
}

test_deny_rds_backup_too_short if {
    rc := make_rc({"backup_retention_period": 3})
    count(rds.deny) > 0 with input as make_input([rc])
}

test_allow_rds_backup_7_days if {
    rc := make_rc({"backup_retention_period": 7})
    deny_msgs := rds.deny with input as make_input([rc])
    not any_msg_contains(deny_msgs, "backup")
}

test_skip_backup_check_for_replica if {
    rc := make_rc({
        "backup_retention_period": 0,
        "replicate_source_db": "arn:aws:rds:us-east-1:123456789:db:primary",
    })
    deny_msgs := rds.deny with input as make_input([rc])
    not any_msg_contains(deny_msgs, "backup")
}

# === Environment-aware: production deny vs dev warn for deletion_protection ===

test_prod_deny_no_deletion_protection if {
    rc := make_rc({
        "deletion_protection": false,
        "tags_all": {"Environment": "production", "Project": "obs", "ManagedBy": "terraform"},
    })
    deny_msgs := rds.deny with input as make_input([rc])
    any_msg_contains(deny_msgs, "deletion_protection")
}

test_dev_warn_no_deletion_protection if {
    rc := make_rc({
        "deletion_protection": false,
        "tags_all": {"Environment": "dev", "Project": "obs", "ManagedBy": "terraform"},
    })
    warn_msgs := rds.warn with input as make_input([rc])
    any_msg_contains(warn_msgs, "deletion_protection")
}

# === Environment-aware: production deny vs dev warn for multi_az ===

test_prod_deny_no_multi_az if {
    rc := make_rc({
        "multi_az": false,
        "tags_all": {"Environment": "production", "Project": "obs", "ManagedBy": "terraform"},
    })
    deny_msgs := rds.deny with input as make_input([rc])
    any_msg_contains(deny_msgs, "multi_az")
}

test_dev_warn_no_multi_az if {
    rc := make_rc({
        "multi_az": false,
        "tags_all": {"Environment": "dev", "Project": "obs", "ManagedBy": "terraform"},
    })
    warn_msgs := rds.warn with input as make_input([rc])
    any_msg_contains(warn_msgs, "multi_az")
}

# === WARN: performance_insights ===

test_warn_rds_no_performance_insights if {
    rc := make_rc({"performance_insights_enabled": false})
    count(rds.warn) > 0 with input as make_input([rc])
}

# === Fully compliant (dev) = zero deny, zero warn ===

test_fully_compliant_rds_dev if {
    rc := make_rc({})
    count(rds.deny) == 0 with input as make_input([rc])
    count(rds.warn) == 0 with input as make_input([rc])
}

# === Fully compliant (production) = zero deny, zero warn ===

test_fully_compliant_rds_prod if {
    rc := make_rc({
        "tags_all": {"Environment": "production", "Project": "obs", "ManagedBy": "terraform"},
    })
    count(rds.deny) == 0 with input as make_input([rc])
    count(rds.warn) == 0 with input as make_input([rc])
}

# --- Helpers ---

any_msg_contains(msgs, substr) if {
    some msg in msgs
    contains(msg, substr)
}
