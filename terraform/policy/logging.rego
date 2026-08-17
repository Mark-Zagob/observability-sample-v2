# =============================================================
# Logging & CloudWatch Policies
# =============================================================
# Kiểm tra: log group encryption, retention period
# =============================================================

package terraform.logging

import rego.v1

# ----- DENY: CloudWatch Log Group phải có KMS encryption -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_cloudwatch_log_group"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    kms_key := object.get(rc.change.after, "kms_key_id", null)
    kms_key == null

    after_unknown := object.get(rc.change, "after_unknown", {})
    not object.get(after_unknown, "kms_key_id", false)

    msg := sprintf(
        "🔴 [SECURITY] CloudWatch Log Group '%s' phải có kms_key_id để encrypt logs at rest.",
        [rc.address]
    )
}

# ----- WARN: Log Group nên có retention policy hợp lý -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_cloudwatch_log_group"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    retention := object.get(rc.change.after, "retention_in_days", 0)
    retention < 30
    retention != 0

    msg := sprintf(
        "🟡 [COMPLIANCE] Log Group '%s' retention = %d ngày (nên >= 30 cho audit trail).",
        [rc.address, retention]
    )
}

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_cloudwatch_log_group"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    retention := object.get(rc.change.after, "retention_in_days", 0)
    retention == 0

    msg := sprintf(
        "🟡 [COST] Log Group '%s' không set retention (logs giữ vĩnh viễn = tốn chi phí). Nên set retention_in_days.",
        [rc.address]
    )
}
