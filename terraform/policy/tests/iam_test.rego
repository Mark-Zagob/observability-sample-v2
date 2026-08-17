# =============================================================
# IAM Policy Unit Tests
# =============================================================

package terraform.iam_test

import rego.v1

import data.terraform.iam

make_input(rc) := {"resource_changes": [rc]}

# === DENY: wildcard action ===

test_deny_iam_wildcard_action if {
    rc := {
        "address": "module.security.aws_iam_role_policy.test",
        "type": "aws_iam_role_policy",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "policy": json.marshal({
                "Version": "2012-10-17",
                "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}],
            }),
        }},
    }
    count(iam.deny) > 0 with input as make_input(rc)
}

test_allow_iam_scoped_action if {
    rc := {
        "address": "module.security.aws_iam_role_policy.test",
        "type": "aws_iam_role_policy",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "policy": json.marshal({
                "Version": "2012-10-17",
                "Statement": [{"Effect": "Allow", "Action": ["logs:CreateLogGroup", "logs:PutLogEvents"], "Resource": "arn:aws:logs:*:*:log-group:/ecs/*"}],
            }),
        }},
    }
    count(iam.deny) == 0 with input as make_input(rc)
}

# === DENY: dangerous service wildcard with Resource = * ===

test_deny_iam_dangerous_wildcard_resource if {
    rc := {
        "address": "module.security.aws_iam_role_policy.test",
        "type": "aws_iam_role_policy",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "policy": json.marshal({
                "Version": "2012-10-17",
                "Statement": [{"Effect": "Allow", "Action": "s3:*", "Resource": "*"}],
            }),
        }},
    }
    count(iam.deny) > 0 with input as make_input(rc)
}

# === WARN: admin managed policy ===

test_warn_admin_managed_policy if {
    rc := {
        "address": "module.security.aws_iam_role_policy_attachment.test",
        "type": "aws_iam_role_policy_attachment",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess",
        }},
    }
    count(iam.warn) > 0 with input as make_input(rc)
}

test_no_warn_scoped_managed_policy if {
    rc := {
        "address": "module.security.aws_iam_role_policy_attachment.test",
        "type": "aws_iam_role_policy_attachment",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "policy_arn": "arn:aws:iam::aws:policy/AmazonECSTaskExecutionRolePolicy",
        }},
    }
    count(iam.warn) == 0 with input as make_input(rc)
}
