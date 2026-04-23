# =============================================================
# Secrets Manager Policies
# =============================================================
# Kiểm tra: CMK encryption, recovery window
# =============================================================

package terraform.secrets

import rego.v1

# ----- DENY: Secret phải được encrypt bằng CMK (không dùng default AWS key) -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_secretsmanager_secret"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    kms_key := object.get(rc.change.after, "kms_key_id", null)
    kms_key == null

    msg := sprintf(
        "🔴 [SECURITY] Secret '%s' phải dùng CMK (kms_key_id) thay vì default AWS managed key.",
        [rc.address]
    )
}

# ----- WARN: Recovery window nên >= 7 ngày -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_secretsmanager_secret"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    window := object.get(rc.change.after, "recovery_window_in_days", 30)
    window < 7

    msg := sprintf(
        "🟡 [WARNING] Secret '%s' có recovery_window = %d ngày (nên >= 7 để tránh xóa nhầm).",
        [rc.address, window]
    )
}
