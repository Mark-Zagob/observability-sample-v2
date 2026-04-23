# =============================================================
# KMS & Encryption Policies
# =============================================================
# Kiểm tra: key rotation, deletion window
# =============================================================

package terraform.kms

import rego.v1

# ----- DENY: KMS key phải có auto-rotation [CIS-AWS-3.8] [SOC2-CC6.1] -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_kms_key"
    rc.mode == "managed"
    rc.change.after.enable_key_rotation != true
    msg := sprintf(
        "🔴 [SECURITY][CIS-AWS-3.8] KMS key '%s' phải bật enable_key_rotation",
        [rc.address]
    )
}

# ----- WARN: KMS deletion window nên >= 14 ngày -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_kms_key"
    rc.mode == "managed"
    window := rc.change.after.deletion_window_in_days
    window < 14
    msg := sprintf(
        "🟡 [WARNING] KMS key '%s' có deletion_window = %d ngày (nên >= 14)",
        [rc.address, window]
    )
}
