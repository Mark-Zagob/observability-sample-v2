# =============================================================
# General Policy Unit Tests
# =============================================================

package terraform.general_test

import rego.v1

import data.terraform.general

make_input(rc) := {"resource_changes": [rc]}

# === DENY: missing required tags ===

test_deny_missing_tags if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "tags_all": {"Project": "obs"},
        }},
    }
    count(general.deny) > 0 with input as make_input(rc)
}

test_allow_all_tags_present if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "tags_all": {
                "Project": "obs",
                "Environment": "dev",
                "ManagedBy": "terraform",
            },
            "instance_class": "db.t3.micro",
            "identifier": "obs-dev-db",
        }},
    }
    deny_msgs := general.deny with input as make_input(rc)
    not any_tag_deny(deny_msgs)
}

any_tag_deny(msgs) if {
    some msg in msgs
    contains(msg, "tag")
}

# null tags_all should deny cleanly (not OPA error)
test_deny_null_tags_all if {
    rc := {
        "address": "module.database.aws_kms_key.test",
        "type": "aws_kms_key",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {}},
    }
    count(general.deny) > 0 with input as make_input(rc)
}

# skip tag check for delete actions
test_skip_tag_check_on_delete if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["delete"], "after": {}},
    }
    deny_msgs := general.deny with input as make_input(rc)
    not any_tag_deny(deny_msgs)
}

# non-taggable types should be skipped
test_skip_non_taggable_type if {
    rc := {
        "address": "module.network.aws_vpc.test",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "tags_all": {},
        }},
    }
    deny_msgs := general.deny with input as make_input(rc)
    not any_tag_deny(deny_msgs)
}

# === DENY: expensive RDS class ===

test_deny_expensive_rds if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "instance_class": "db.r5.8xlarge",
            "tags_all": {
                "Project": "obs",
                "Environment": "dev",
                "ManagedBy": "terraform",
            },
            "identifier": "obs-dev-db",
        }},
    }
    deny_msgs := general.deny with input as make_input(rc)
    any_cost_deny(deny_msgs)
}

any_cost_deny(msgs) if {
    some msg in msgs
    contains(msg, "COST")
}

test_allow_cheap_rds if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "instance_class": "db.t3.micro",
            "tags_all": {
                "Project": "obs",
                "Environment": "dev",
                "ManagedBy": "terraform",
            },
            "identifier": "obs-dev-db",
        }},
    }
    deny_msgs := general.deny with input as make_input(rc)
    not any_cost_deny(deny_msgs)
}

# === WARN: naming convention ===

test_warn_bad_naming if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "identifier": "mydb-production",
        }},
    }
    count(general.warn) > 0 with input as make_input(rc)
}

test_no_warn_good_naming if {
    rc := {
        "address": "module.database.aws_db_instance.test",
        "type": "aws_db_instance",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "identifier": "obs-production-postgres",
        }},
    }
    count(general.warn) == 0 with input as make_input(rc)
}
