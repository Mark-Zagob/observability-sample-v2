# =============================================================
# KMS Policy Unit Tests
# =============================================================

package terraform.kms_test

import rego.v1

import data.terraform.kms

make_input(rc) := {"resource_changes": [rc]}

# === DENY: key rotation ===

test_deny_kms_no_rotation if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_key_rotation": false,
            "deletion_window_in_days": 30,
        }},
    }
    count(kms.deny) > 0 with input as make_input(rc)
}

test_allow_kms_with_rotation if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_key_rotation": true,
            "deletion_window_in_days": 30,
        }},
    }
    count(kms.deny) == 0 with input as make_input(rc)
}

# === WARN: deletion window ===

test_warn_kms_short_deletion_window if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_key_rotation": true,
            "deletion_window_in_days": 7,
        }},
    }
    count(kms.warn) > 0 with input as make_input(rc)
}

test_no_warn_kms_good_deletion_window if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_key_rotation": true,
            "deletion_window_in_days": 14,
        }},
    }
    count(kms.warn) == 0 with input as make_input(rc)
}

test_no_warn_kms_max_deletion_window if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_key_rotation": true,
            "deletion_window_in_days": 30,
        }},
    }
    count(kms.warn) == 0 with input as make_input(rc)
}
