# =============================================================
# Helpers Unit Tests — Environment Detection
# =============================================================

package terraform.helpers_test

import rego.v1

import data.terraform.helpers

make_input(rcs) := {"resource_changes": rcs}

tagged_rc(env) := {
    "address": "module.database.aws_db_instance.test",
    "type": "aws_db_instance",
    "mode": "managed",
    "change": {"actions": ["create"], "after": {
        "tags_all": {"Environment": env, "Project": "obs", "ManagedBy": "terraform"},
    }},
}

# === is_production ===

test_detect_production if {
    helpers.is_production with input as make_input([tagged_rc("production")])
}

test_detect_prod if {
    helpers.is_production with input as make_input([tagged_rc("prod")])
}

test_detect_Production_case_insensitive if {
    helpers.is_production with input as make_input([tagged_rc("Production")])
}

test_not_production_for_dev if {
    not helpers.is_production with input as make_input([tagged_rc("dev")])
}

# === is_dev ===

test_detect_dev if {
    helpers.is_dev with input as make_input([tagged_rc("dev")])
}

test_detect_development if {
    helpers.is_dev with input as make_input([tagged_rc("development")])
}

# === is_staging ===

test_detect_staging if {
    helpers.is_staging with input as make_input([tagged_rc("staging")])
}

test_detect_stg if {
    helpers.is_staging with input as make_input([tagged_rc("stg")])
}

# === is_strict ===

test_strict_for_production if {
    helpers.is_strict with input as make_input([tagged_rc("production")])
}

test_strict_for_unknown if {
    helpers.is_strict with input as make_input([{
        "address": "module.test.aws_vpc.test",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {}},
    }])
}

test_not_strict_for_dev if {
    not helpers.is_strict with input as make_input([tagged_rc("dev")])
}

test_not_strict_for_staging if {
    not helpers.is_strict with input as make_input([tagged_rc("staging")])
}
