# =============================================================
# Logging Policy Unit Tests
# =============================================================

package terraform.logging_test

import rego.v1

import data.terraform.logging

make_input(rc) := {"resource_changes": [rc]}

# === DENY: log group without KMS ===

test_deny_log_group_no_kms if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "/ecs/test",
            "retention_in_days": 90,
        }},
    }
    count(logging.deny) > 0 with input as make_input(rc)
}

test_allow_log_group_with_kms if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "/ecs/test",
            "retention_in_days": 90,
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
        }},
    }
    count(logging.deny) == 0 with input as make_input(rc)
}

# skip on delete
test_skip_log_group_on_delete if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["delete"], "after": {}},
    }
    count(logging.deny) == 0 with input as make_input(rc)
}

# === WARN: short retention ===

test_warn_log_group_short_retention if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "/ecs/test",
            "retention_in_days": 7,
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
        }},
    }
    count(logging.warn) > 0 with input as make_input(rc)
}

# === WARN: no retention (logs kept forever) ===

test_warn_log_group_no_retention if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "/ecs/test",
            "retention_in_days": 0,
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
        }},
    }
    count(logging.warn) > 0 with input as make_input(rc)
}

test_no_warn_log_group_good_retention if {
    rc := {
        "address": "module.database.aws_cloudwatch_log_group.test",
        "type": "aws_cloudwatch_log_group",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "name": "/ecs/test",
            "retention_in_days": 90,
            "kms_key_id": "arn:aws:kms:us-east-1:123456789:key/abc-123",
        }},
    }
    count(logging.warn) == 0 with input as make_input(rc)
}
