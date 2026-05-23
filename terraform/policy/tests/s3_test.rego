# =============================================================
# S3 Policy Unit Tests
# =============================================================

package terraform.s3_test

import rego.v1

import data.terraform.s3

make_input(rc) := {"resource_changes": [rc]}

# === DENY: public access block ===

test_deny_s3_public_acls_not_blocked if {
    rc := {
        "address": "module.storage.aws_s3_bucket_public_access_block.test",
        "type": "aws_s3_bucket_public_access_block",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "block_public_acls": false,
            "block_public_policy": true,
            "ignore_public_acls": true,
            "restrict_public_buckets": true,
        }},
    }
    count(s3.deny) > 0 with input as make_input(rc)
}

test_deny_s3_public_policy_not_blocked if {
    rc := {
        "address": "module.storage.aws_s3_bucket_public_access_block.test",
        "type": "aws_s3_bucket_public_access_block",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "block_public_acls": true,
            "block_public_policy": false,
            "ignore_public_acls": true,
            "restrict_public_buckets": true,
        }},
    }
    count(s3.deny) > 0 with input as make_input(rc)
}

test_allow_s3_all_public_access_blocked if {
    rc := {
        "address": "module.storage.aws_s3_bucket_public_access_block.test",
        "type": "aws_s3_bucket_public_access_block",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "block_public_acls": true,
            "block_public_policy": true,
            "ignore_public_acls": true,
            "restrict_public_buckets": true,
        }},
    }
    count(s3.deny) == 0 with input as make_input(rc)
}

# === DENY: encryption configuration ===

test_deny_s3_no_encryption_rule if {
    rc := {
        "address": "module.storage.aws_s3_bucket_server_side_encryption_configuration.test",
        "type": "aws_s3_bucket_server_side_encryption_configuration",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {}},
    }
    count(s3.deny) > 0 with input as make_input(rc)
}

test_allow_s3_with_encryption_rule if {
    rc := {
        "address": "module.storage.aws_s3_bucket_server_side_encryption_configuration.test",
        "type": "aws_s3_bucket_server_side_encryption_configuration",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": "aws:kms"}}],
        }},
    }
    count(s3.deny) == 0 with input as make_input(rc)
}

# === WARN: versioning ===

test_warn_s3_versioning_disabled if {
    rc := {
        "address": "module.storage.aws_s3_bucket_versioning.test",
        "type": "aws_s3_bucket_versioning",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "versioning_configuration": [{"status": "Disabled"}],
        }},
    }
    count(s3.warn) > 0 with input as make_input(rc)
}

test_no_warn_s3_versioning_enabled if {
    rc := {
        "address": "module.storage.aws_s3_bucket_versioning.test",
        "type": "aws_s3_bucket_versioning",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "versioning_configuration": [{"status": "Enabled"}],
        }},
    }
    count(s3.warn) == 0 with input as make_input(rc)
}
