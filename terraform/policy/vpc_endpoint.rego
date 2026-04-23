# =============================================================
# VPC Endpoint Policies
# =============================================================
# Kiểm tra: private DNS, endpoint type configuration
#
# Compliance references:
#   - AWS Well-Architected SEC05-BP03: Automate network protection
#   - CIS AWS 5.3: Ensure S3 access is via VPC endpoint
# =============================================================

package terraform.vpc_endpoint

import rego.v1

# ----- WARN: Interface endpoint nên bật private DNS -----
# [Well-Architected-SEC05-BP03]

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_vpc_endpoint"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    vpc_type := object.get(rc.change.after, "vpc_endpoint_type", "Gateway")
    vpc_type == "Interface"

    private_dns := object.get(rc.change.after, "private_dns_enabled", false)
    private_dns != true

    msg := sprintf(
        "🟡 [NETWORK] VPC endpoint '%s' (Interface) nên bật private_dns_enabled = true để route traffic qua endpoint.",
        [rc.address]
    )
}
