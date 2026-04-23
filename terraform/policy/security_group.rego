# =============================================================
# Security Group Policies
# =============================================================
# Kiểm tra: open ingress, SSH from 0.0.0.0/0, broad egress
# =============================================================

package terraform.security_group

import rego.v1

# ----- DENY: Không cho ingress 0.0.0.0/0 trên SG không phải ALB -----
# ALB SG thường chứa "alb" trong tên — cho phép 80/443 từ internet

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_security_group_rule"
    rc.mode == "managed"

    rule := rc.change.after
    rule.type == "ingress"

    cidrs := object.get(rule, "cidr_blocks", [])
    some cidr in cidrs
    cidr == "0.0.0.0/0"

    from_port := object.get(rule, "from_port", 0)
    to_port := object.get(rule, "to_port", 0)

    not is_standard_web_port(from_port, to_port)

    msg := sprintf(
        "🔴 [NETWORK] SG rule '%s' cho phép ingress từ 0.0.0.0/0 trên port %d-%d. Chỉ ALB mới được mở public.",
        [rc.address, from_port, to_port]
    )
}

# ----- DENY: SSH (port 22) từ 0.0.0.0/0 -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_security_group_rule"
    rc.mode == "managed"

    rule := rc.change.after
    rule.type == "ingress"

    cidrs := object.get(rule, "cidr_blocks", [])
    some cidr in cidrs
    cidr == "0.0.0.0/0"

    from_port := object.get(rule, "from_port", 0)
    to_port := object.get(rule, "to_port", 0)
    port_in_range(22, from_port, to_port)

    msg := sprintf(
        "🔴 [CRITICAL] SG rule '%s' mở SSH (port 22) từ 0.0.0.0/0. Dùng SSM Session Manager hoặc VPN.",
        [rc.address]
    )
}

# ----- WARN: Egress 0.0.0.0/0 trên tất cả ports -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_security_group_rule"
    rc.mode == "managed"

    rule := rc.change.after
    rule.type == "egress"

    cidrs := object.get(rule, "cidr_blocks", [])
    some cidr in cidrs
    cidr == "0.0.0.0/0"

    from_port := object.get(rule, "from_port", 0)
    to_port := object.get(rule, "to_port", 0)
    from_port == 0
    to_port == 0

    msg := sprintf(
        "🟡 [NETWORK] SG rule '%s' có egress 0.0.0.0/0 trên all ports. Nên restrict egress theo principle of least privilege.",
        [rc.address]
    )
}

# ----- Helpers -----

is_standard_web_port(from_port, to_port) if {
    from_port == 80
    to_port == 80
}

is_standard_web_port(from_port, to_port) if {
    from_port == 443
    to_port == 443
}

port_in_range(port, from_port, to_port) if {
    port >= from_port
    port <= to_port
}

# ----- DENY: Inline ingress 0.0.0.0/0 trong aws_security_group -----
# Bắt cả trường hợp SG dùng inline ingress {} block thay vì aws_security_group_rule

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_security_group"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]

    some rule in rc.change.after.ingress
    some cidr in object.get(rule, "cidr_blocks", [])
    cidr == "0.0.0.0/0"

    from_port := object.get(rule, "from_port", 0)
    to_port := object.get(rule, "to_port", 0)
    not is_standard_web_port(from_port, to_port)

    msg := sprintf(
        "🔴 [NETWORK] SG '%s' có inline ingress 0.0.0.0/0 trên port %d-%d. Dùng separate aws_security_group_rule thay thế.",
        [rc.address, from_port, to_port]
    )
}

# ----- DENY: Inline SSH (port 22) từ 0.0.0.0/0 -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_security_group"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]

    some rule in rc.change.after.ingress
    some cidr in object.get(rule, "cidr_blocks", [])
    cidr == "0.0.0.0/0"

    from_port := object.get(rule, "from_port", 0)
    to_port := object.get(rule, "to_port", 0)
    port_in_range(22, from_port, to_port)

    msg := sprintf(
        "🔴 [CRITICAL] SG '%s' có inline rule mở SSH (port 22) từ 0.0.0.0/0.",
        [rc.address]
    )
}
