# =============================================================
# Secrets Manager Policy Unit Tests
# =============================================================

package terraform.secrets_test

import rego.v1

import data.terraform.secrets

make_input(rc) := {"resource_changes": [rc]}

# === DENY: missing CMK ===

test_deny_secret_no_cmk if {
    rc := {
        "address": "module.database.aws_secretsmanager_secret.test",
        "type": "aws_secretsmanager_secret",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "test-secret",
        }},
    }
    count(secrets.deny) > 0 with input as make_input(rc)
}

test_allow_secret_with_cmk if {
    rc := {
        "address": "module.database.aws_secretsmanager_secret.test",
        "type": "aws_secretsmanager_secret",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "test-secret",
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
        }},
    }
    count(secrets.deny) == 0 with input as make_input(rc)
}

# skip on delete
test_skip_secret_on_delete if {
    rc := {
        "address": "module.database.aws_secretsmanager_secret.test",
        "type": "aws_secretsmanager_secret",
        "mode": "managed",
        "change": {"actions": ["delete"], "after": {}},
    }
    count(secrets.deny) == 0 with input as make_input(rc)
}

# === WARN: recovery window ===

test_warn_secret_short_recovery if {
    rc := {
        "address": "module.database.aws_secretsmanager_secret.test",
        "type": "aws_secretsmanager_secret",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "test-secret",
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
            "recovery_window_in_days": 0,
        }},
    }
    count(secrets.warn) > 0 with input as make_input(rc)
}

test_no_warn_secret_good_recovery if {
    rc := {
        "address": "module.database.aws_secretsmanager_secret.test",
        "type": "aws_secretsmanager_secret",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "test-secret",
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
            "recovery_window_in_days": 30,
        }},
    }
    count(secrets.warn) == 0 with input as make_input(rc)
}
