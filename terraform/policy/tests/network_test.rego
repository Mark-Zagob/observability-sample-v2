# =============================================================
# Network Policy Unit Tests
# =============================================================

package terraform.network_test

import rego.v1

import data.terraform.network

make_input(rcs) := {"resource_changes": rcs}

# === DENY: VPC without DNS hostnames ===

test_deny_vpc_no_dns_hostnames if {
    rcs := [{
        "address": "module.network.aws_vpc.main",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_dns_hostnames": false,
            "enable_dns_support": true,
        }},
    }]
    count(network.deny) > 0 with input as make_input(rcs)
}

test_deny_vpc_no_dns_support if {
    rcs := [{
        "address": "module.network.aws_vpc.main",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_dns_hostnames": true,
            "enable_dns_support": false,
        }},
    }]
    count(network.deny) > 0 with input as make_input(rcs)
}

test_allow_vpc_dns_enabled if {
    rcs := [{
        "address": "module.network.aws_vpc.main",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_dns_hostnames": true,
            "enable_dns_support": true,
        }},
    }]
    count(network.deny) == 0 with input as make_input(rcs)
}

# === WARN: VPC without flow logs ===

test_warn_vpc_no_flow_logs if {
    rcs := [{
        "address": "module.network.aws_vpc.main",
        "type": "aws_vpc",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "enable_dns_hostnames": true,
            "enable_dns_support": true,
        }},
    }]
    count(network.warn) > 0 with input as make_input(rcs)
}

test_no_warn_vpc_with_flow_logs if {
    rcs := [
        {
            "address": "module.network.aws_vpc.main",
            "type": "aws_vpc",
            "mode": "managed",
            "change": {"actions": ["create"], "after": {
                "enable_dns_hostnames": true,
                "enable_dns_support": true,
            }},
        },
        {
            "address": "module.network.aws_flow_log.main",
            "type": "aws_flow_log",
            "mode": "managed",
            "change": {"actions": ["create"], "after": {
                "traffic_type": "ALL",
            }},
        },
    ]
    count(network.warn) == 0 with input as make_input(rcs)
}
