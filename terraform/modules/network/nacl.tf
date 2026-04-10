#--------------------------------------------------------------
# Network ACLs — Data Tier Isolation
#--------------------------------------------------------------
# Restricts Data subnet traffic to only Private subnets on
# specific database ports. Provides defense-in-depth beyond
# Security Groups (CIS Benchmark 5.1).
#
# Uncomment when ready to enforce NACL-level isolation.
#--------------------------------------------------------------

# resource "aws_network_acl" "data" {
#   vpc_id     = aws_vpc.this.id
#   subnet_ids = [for k, v in aws_subnet.data : v.id]
#
#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-nacl-data"
#     Tier = "data"
#   })
# }

#--------------------------------------------------------------
# Inbound Rules — Allow only from Private subnets
#--------------------------------------------------------------

# # PostgreSQL / Aurora (5432) from Private subnets
# resource "aws_network_acl_rule" "data_inbound_postgres" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 100 + index(keys(local.az_map), each.key)
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.private_cidrs[each.key]
#   from_port      = 5432
#   to_port        = 5432
# }

# # MySQL / Aurora MySQL (3306) from Private subnets
# resource "aws_network_acl_rule" "data_inbound_mysql" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 110 + index(keys(local.az_map), each.key)
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.private_cidrs[each.key]
#   from_port      = 3306
#   to_port        = 3306
# }

# # Redis / ElastiCache (6379) from Private subnets
# resource "aws_network_acl_rule" "data_inbound_redis" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 120 + index(keys(local.az_map), each.key)
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.private_cidrs[each.key]
#   from_port      = 6379
#   to_port        = 6379
# }

# # Ephemeral ports — return traffic for TCP connections
# resource "aws_network_acl_rule" "data_inbound_ephemeral" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 900 + index(keys(local.az_map), each.key)
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.private_cidrs[each.key]
#   from_port      = 1024
#   to_port        = 65535
# }

# # Deny all other inbound (explicit — NACL default is deny,
# # but making it visible aids auditability)
# resource "aws_network_acl_rule" "data_inbound_deny_all" {
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 32766
#   egress         = false
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }

#--------------------------------------------------------------
# Outbound Rules — Allow responses back to Private subnets
#--------------------------------------------------------------

# # Ephemeral ports — response traffic back to Private subnets
# resource "aws_network_acl_rule" "data_outbound_ephemeral" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 100 + index(keys(local.az_map), each.key)
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.private_cidrs[each.key]
#   from_port      = 1024
#   to_port        = 65535
# }

# # Deny all other outbound (explicit)
# resource "aws_network_acl_rule" "data_outbound_deny_all" {
#   network_acl_id = aws_network_acl.data.id
#   rule_number    = 32766
#   egress         = true
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }
