# =============================================================
# Network / VPC Policies
# =============================================================
# Kiểm tra: VPC DNS settings, flow logs existence
#
# Compliance references:
#   - CIS AWS 2.9: Ensure VPC flow logging is enabled
#   - AWS Well-Architected SEC05-BP02: Control traffic at all layers
# =============================================================

package terraform.network

import rego.v1

# ----- DENY: VPC phải bật DNS hostnames và DNS support -----
# [CIS-AWS-2.9] [Well-Architected-SEC05]

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_vpc"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    dns_hostnames := object.get(rc.change.after, "enable_dns_hostnames", false)
    dns_hostnames != true

    msg := sprintf(
        "🔴 [NETWORK] VPC '%s' phải bật enable_dns_hostnames = true (cần cho VPC endpoints và service discovery).",
        [rc.address]
    )
}

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_vpc"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    dns_support := object.get(rc.change.after, "enable_dns_support", true)
    dns_support != true

    msg := sprintf(
        "🔴 [NETWORK] VPC '%s' phải bật enable_dns_support = true.",
        [rc.address]
    )
}

# ----- WARN: VPC nên có flow logs -----
# Kiểm tra: nếu có aws_vpc nhưng không có aws_flow_log trong cùng plan
# [CIS-AWS-3.9] Ensure VPC flow logging is enabled in all VPCs

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_vpc"
    rc.mode == "managed"

    some action in rc.change.actions
    action != "delete"

    not has_flow_log_in_plan

    msg := sprintf(
        "🟡 [COMPLIANCE][CIS-AWS-3.9] VPC '%s' nên có VPC Flow Logs để audit network traffic.",
        [rc.address]
    )
}

has_flow_log_in_plan if {
    some rc in input.resource_changes
    rc.type == "aws_flow_log"
    rc.mode == "managed"
}
