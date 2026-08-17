# =============================================================
# VPC Endpoint Policy Unit Tests
# =============================================================

package terraform.vpc_endpoint_test

import rego.v1

import data.terraform.vpc_endpoint

make_input(rc) := {"resource_changes": [rc]}

# === WARN: interface endpoint without private DNS ===

test_warn_endpoint_no_private_dns if {
    rc := {
        "address": "module.vpc_endpoints.aws_vpc_endpoint.ssm",
        "type": "aws_vpc_endpoint",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "vpc_endpoint_type": "Interface",
            "private_dns_enabled": false,
            "service_name": "com.amazonaws.us-east-1.ssm",
        }},
    }
    count(vpc_endpoint.warn) > 0 with input as make_input(rc)
}

test_no_warn_endpoint_with_private_dns if {
    rc := {
        "address": "module.vpc_endpoints.aws_vpc_endpoint.ssm",
        "type": "aws_vpc_endpoint",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "vpc_endpoint_type": "Interface",
            "private_dns_enabled": true,
            "service_name": "com.amazonaws.us-east-1.ssm",
        }},
    }
    count(vpc_endpoint.warn) == 0 with input as make_input(rc)
}

# gateway endpoints should not trigger this rule
test_skip_gateway_endpoint if {
    rc := {
        "address": "module.vpc_endpoints.aws_vpc_endpoint.s3",
        "type": "aws_vpc_endpoint",
        "mode": "managed",
        "change": {"actions": ["create"], "after": {
            "vpc_endpoint_type": "Gateway",
            "service_name": "com.amazonaws.us-east-1.s3",
        }},
    }
    count(vpc_endpoint.warn) == 0 with input as make_input(rc)
}
