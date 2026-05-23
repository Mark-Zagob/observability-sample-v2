# =============================================================
# IAM Security Policies
# =============================================================
# Kiểm tra: wildcard actions, wildcard resources, trust policy,
#           admin access attachment
# =============================================================

package terraform.iam

import rego.v1

# ----- DENY: IAM policy không được dùng Action = "*" -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_iam_role_policy"
    rc.mode == "managed"

    policy_doc := rc.change.after.policy
    parsed := json.unmarshal(policy_doc)
    some stmt in parsed.Statement
    stmt.Effect == "Allow"
    actions := to_list(stmt.Action)
    some action in actions
    action == "*"

    msg := sprintf(
        "🔴 [SECURITY] IAM inline policy '%s' dùng Action = '*' (wildcard). Phải dùng least-privilege.",
        [rc.address]
    )
}

# ----- DENY: IAM policy không được dùng Resource = "*" với dangerous actions -----

dangerous_action_prefixes := [
    "iam:*", "sts:*", "s3:*", "ec2:*", "rds:*",
    "kms:*", "secretsmanager:*", "lambda:*",
]

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_iam_role_policy"
    rc.mode == "managed"

    policy_doc := rc.change.after.policy
    parsed := json.unmarshal(policy_doc)
    some stmt in parsed.Statement
    stmt.Effect == "Allow"
    resources := to_list(stmt.Resource)
    some resource in resources
    resource == "*"

    actions := to_list(stmt.Action)
    some action in actions
    some prefix in dangerous_action_prefixes
    action == prefix

    msg := sprintf(
        "🔴 [SECURITY] IAM inline policy '%s' dùng Resource = '*' với action '%s'. Phải scope resource cụ thể.",
        [rc.address, action]
    )
}

# ----- DENY: IAM role trust policy không được allow external accounts không nằm trong allow-list -----

# Thêm trusted account IDs vào đây (account của bạn + partners)
trusted_account_ids := {"730335245469"}

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_iam_role"
    rc.mode == "managed"

    trust_doc := rc.change.after.assume_role_policy
    parsed := json.unmarshal(trust_doc)
    some stmt in parsed.Statement
    stmt.Effect == "Allow"

    principals := to_list(object.get(stmt, "Principal", {}))
    some principal in principals

    is_string(principal)
    contains(principal, ":root")
    account_id := extract_account_id(principal)
    account_id != ""
    not account_id in trusted_account_ids

    msg := sprintf(
        "🔴 [SECURITY] IAM role '%s' trust policy cho phép account '%s' không nằm trong trusted list.",
        [rc.address, account_id]
    )
}

# ----- WARN: Gắn AdministratorAccess managed policy -----

admin_managed_policies := [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/PowerUserAccess",
]

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_iam_role_policy_attachment"
    rc.mode == "managed"
    policy_arn := rc.change.after.policy_arn
    some admin_arn in admin_managed_policies
    policy_arn == admin_arn
    msg := sprintf(
        "🟡 [SECURITY] IAM attachment '%s' gắn managed policy '%s'. Nên dùng least-privilege policy.",
        [rc.address, policy_arn]
    )
}

# ----- Helpers -----

to_list(x) := [x] if {
    is_string(x)
}

to_list(x) := x if {
    is_array(x)
}

to_list(x) := [] if {
    not is_string(x)
    not is_array(x)
}

extract_account_id(arn) := id if {
    parts := split(arn, ":")
    count(parts) >= 5
    id := parts[4]
}

extract_account_id(arn) := "" if {
    parts := split(arn, ":")
    count(parts) < 5
}
