# =============================================================
# Security Group Policy Unit Tests
# =============================================================

package terraform.security_group_test

import rego.v1

import data.terraform.security_group

make_input(rc) := {"resource_changes": [rc]}

# === DENY: open ingress on non-web port ===

test_deny_sg_open_ingress_non_web if {
    rc := {
        "address": "module.security.aws_security_group_rule.test",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "ingress",
            "from_port": 5432,
            "to_port": 5432,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "tcp",
        }},
    }
    count(security_group.deny) > 0 with input as make_input(rc)
}

test_allow_sg_web_80_from_internet if {
    rc := {
        "address": "module.security.aws_security_group_rule.alb_http",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "ingress",
            "from_port": 80,
            "to_port": 80,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "tcp",
        }},
    }
    deny_msgs := security_group.deny with input as make_input(rc)
    not any_non_ssh_deny(deny_msgs)
}

any_non_ssh_deny(msgs) if {
    some msg in msgs
    contains(msg, "NETWORK")
    not contains(msg, "SSH")
}

test_allow_sg_web_443_from_internet if {
    rc := {
        "address": "module.security.aws_security_group_rule.alb_https",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "ingress",
            "from_port": 443,
            "to_port": 443,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "tcp",
        }},
    }
    deny_msgs := security_group.deny with input as make_input(rc)
    not any_non_ssh_deny(deny_msgs)
}

# === DENY: SSH from 0.0.0.0/0 ===

test_deny_sg_ssh_from_internet if {
    rc := {
        "address": "module.security.aws_security_group_rule.ssh",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "ingress",
            "from_port": 22,
            "to_port": 22,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "tcp",
        }},
    }
    deny_msgs := security_group.deny with input as make_input(rc)
    any_ssh_deny(deny_msgs)
}

any_ssh_deny(msgs) if {
    some msg in msgs
    contains(msg, "SSH")
}

test_allow_sg_ssh_from_vpc if {
    rc := {
        "address": "module.security.aws_security_group_rule.ssh",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "ingress",
            "from_port": 22,
            "to_port": 22,
            "cidr_blocks": ["10.0.0.0/16"],
            "protocol": "tcp",
        }},
    }
    count(security_group.deny) == 0 with input as make_input(rc)
}

# === WARN: broad egress ===

test_warn_sg_broad_egress if {
    rc := {
        "address": "module.security.aws_security_group_rule.egress",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "egress",
            "from_port": 0,
            "to_port": 0,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "-1",
        }},
    }
    count(security_group.warn) > 0 with input as make_input(rc)
}

test_no_warn_sg_scoped_egress if {
    rc := {
        "address": "module.security.aws_security_group_rule.egress_https",
        "type": "aws_security_group_rule",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "type": "egress",
            "from_port": 443,
            "to_port": 443,
            "cidr_blocks": ["0.0.0.0/0"],
            "protocol": "tcp",
        }},
    }
    count(security_group.warn) == 0 with input as make_input(rc)
}
