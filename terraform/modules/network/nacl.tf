#--------------------------------------------------------------
# Network ACLs — Production Defense-in-Depth
#--------------------------------------------------------------
# Strategy: Each tier gets a dedicated NACL with least-privilege
# rules. NACLs are STATELESS — both inbound and outbound rules
# required. Ephemeral ports (1024-65535) needed for return traffic.
#
# Reference: CIS AWS Benchmark 5.1, AWS Well-Architected SEC05
#
# Architecture:
#   Public  → Internet (80/443), forward to Private (app ports)
#   Private → Receive from Public, connect to Data (DB ports),
#             outbound Internet via NAT (443 for APIs/packages)
#   Data    → Receive ONLY from Private (DB ports), NO Internet
#   Mgmt    → SSH from trusted CIDRs, monitor internal resources
#
# Uncomment each section when ready to enforce.
#--------------------------------------------------------------

# Helper local — full VPC CIDR for broad internal rules
locals {
  vpc_cidr_block = var.vpc_cidr

  # Aggregate CIDR lists for cross-tier references
  # These use values() since the maps are keyed by AZ letter (a, b, c)
  all_private_cidrs = values(local.private_cidrs)
  all_public_cidrs  = values(local.public_cidrs)
  all_data_cidrs    = values(local.data_cidrs)
  all_mgmt_cidrs    = values(local.mgmt_cidrs)
}


########################################################################
# 1. PUBLIC SUBNET NACL
########################################################################
# Purpose: Control traffic at the Internet boundary
# Allow: HTTP/HTTPS from Internet, ephemeral return traffic
# Deny:  Direct SSH/RDP/DB access from Internet
########################################################################

# resource "aws_network_acl" "public" {
#   vpc_id     = aws_vpc.this.id
#   subnet_ids = [for k, v in aws_subnet.public : v.id]
#
#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-nacl-public"
#     Tier = "public"
#   })
# }

#--- INBOUND: What enters Public subnets ---

# # HTTP from Internet (ALB listeners)
# resource "aws_network_acl_rule" "public_inbound_http" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 100
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 80
#   to_port        = 80
# }

# # HTTPS from Internet (ALB listeners + API Gateway)
# resource "aws_network_acl_rule" "public_inbound_https" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 110
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 443
#   to_port        = 443
# }

# # Ephemeral ports — return traffic from Internet (NAT GW responses,
# # package manager downloads, API calls initiated from Private/Mgmt)
# resource "aws_network_acl_rule" "public_inbound_ephemeral" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 900
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 1024
#   to_port        = 65535
# }

# # ❌ DENY SSH from Internet (even if SG misconfigured)
# resource "aws_network_acl_rule" "public_inbound_deny_ssh" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 200
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 22
#   to_port        = 22
# }

# # ❌ DENY RDP from Internet
# resource "aws_network_acl_rule" "public_inbound_deny_rdp" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 210
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 3389
#   to_port        = 3389
# }

# # ❌ DENY Postgres from Internet (defense-in-depth for DB)
# resource "aws_network_acl_rule" "public_inbound_deny_postgres" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 220
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 5432
#   to_port        = 5432
# }

# # ❌ DENY MySQL from Internet
# resource "aws_network_acl_rule" "public_inbound_deny_mysql" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 230
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 3306
#   to_port        = 3306
# }

# # ❌ DENY Redis from Internet
# resource "aws_network_acl_rule" "public_inbound_deny_redis" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 240
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 6379
#   to_port        = 6379
# }

# # Explicit deny all other inbound (audit visibility)
# resource "aws_network_acl_rule" "public_inbound_deny_all" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 32766
#   egress         = false
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }

#--- OUTBOUND: What leaves Public subnets ---

# # HTTP outbound (redirects, health checks)
# resource "aws_network_acl_rule" "public_outbound_http" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 100
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 80
#   to_port        = 80
# }

# # HTTPS outbound (API calls, certificate validation, package downloads)
# resource "aws_network_acl_rule" "public_outbound_https" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 110
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 443
#   to_port        = 443
# }

# # Ephemeral ports outbound — response traffic to Internet clients
# resource "aws_network_acl_rule" "public_outbound_ephemeral" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 900
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 1024
#   to_port        = 65535
# }

# # Explicit deny all other outbound
# resource "aws_network_acl_rule" "public_outbound_deny_all" {
#   network_acl_id = aws_network_acl.public.id
#   rule_number    = 32766
#   egress         = true
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }


########################################################################
# 2. PRIVATE (APP) SUBNET NACL
########################################################################
# Purpose: Isolate app tier — receive traffic from Public (ALB),
#          connect to Data tier (DB), outbound via NAT
# Key:    This is the MOST permissive internal tier because app
#         servers need to talk to many services
########################################################################

# resource "aws_network_acl" "private" {
#   vpc_id     = aws_vpc.this.id
#   subnet_ids = [for k, v in aws_subnet.private : v.id]
#
#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-nacl-private"
#     Tier = "private"
#   })
# }

#--- INBOUND: What enters Private subnets ---

# # Allow ALL TCP from VPC (ALB → App, service-to-service, mgmt → app)
# # Private tier is intentionally broad for internal communication.
# # SGs handle granular port-level control within this tier.
# resource "aws_network_acl_rule" "private_inbound_vpc" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 100
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 1
#   to_port        = 65535
# }

# # Ephemeral return traffic from Internet (via NAT GW responses)
# # When app calls external APIs, responses come back on ephemeral ports
# resource "aws_network_acl_rule" "private_inbound_ephemeral_internet" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 900
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 1024
#   to_port        = 65535
# }

# # ❌ DENY SSH from Internet (should never reach Private directly)
# resource "aws_network_acl_rule" "private_inbound_deny_ssh_internet" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 50
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 22
#   to_port        = 22
# }

# # Explicit deny all other inbound
# resource "aws_network_acl_rule" "private_inbound_deny_all" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 32766
#   egress         = false
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }

#--- OUTBOUND: What leaves Private subnets ---

# # Postgres to Data tier
# resource "aws_network_acl_rule" "private_outbound_postgres" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 100 + index(keys(local.az_map), each.key)
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.data_cidrs[each.key]
#   from_port      = 5432
#   to_port        = 5432
# }

# # MySQL to Data tier
# resource "aws_network_acl_rule" "private_outbound_mysql" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 110 + index(keys(local.az_map), each.key)
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.data_cidrs[each.key]
#   from_port      = 3306
#   to_port        = 3306
# }

# # Redis to Data tier
# resource "aws_network_acl_rule" "private_outbound_redis" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 120 + index(keys(local.az_map), each.key)
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.data_cidrs[each.key]
#   from_port      = 6379
#   to_port        = 6379
# }

# # HTTPS outbound to Internet (via NAT — APIs, package managers, AWS services)
# resource "aws_network_acl_rule" "private_outbound_https" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 200
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 443
#   to_port        = 443
# }

# # HTTP outbound (some package repos, redirects)
# resource "aws_network_acl_rule" "private_outbound_http" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 210
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 80
#   to_port        = 80
# }

# # Ephemeral ports — response traffic back to VPC (ALB, other services)
# resource "aws_network_acl_rule" "private_outbound_ephemeral_vpc" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 900
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 1024
#   to_port        = 65535
# }

# # Explicit deny all other outbound
# resource "aws_network_acl_rule" "private_outbound_deny_all" {
#   network_acl_id = aws_network_acl.private.id
#   rule_number    = 32766
#   egress         = true
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }


########################################################################
# 3. DATA SUBNET NACL
########################################################################
# Purpose: Maximum isolation — ONLY Private subnets can reach DB ports
# This is the MOST restrictive NACL (highest value data lives here)
# No Internet access at all (no NAT route in route table either)
########################################################################

# resource "aws_network_acl" "data" {
#   vpc_id     = aws_vpc.this.id
#   subnet_ids = [for k, v in aws_subnet.data : v.id]
#
#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-nacl-data"
#     Tier = "data"
#   })
# }

#--- INBOUND: What enters Data subnets ---

# # PostgreSQL / Aurora (5432) from Private subnets ONLY
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

# # MySQL / Aurora MySQL (3306) from Private subnets ONLY
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

# # Redis / ElastiCache (6379) from Private subnets ONLY
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

# # Ephemeral ports — return traffic for TCP connections from Private
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

# # Explicit deny all other inbound (audit trail)
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

#--- OUTBOUND: What leaves Data subnets ---

# # Ephemeral ports — response traffic back to Private subnets ONLY
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

# # Explicit deny all other outbound (DB should NEVER initiate
# # connections to Internet or other tiers)
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


########################################################################
# 4. MANAGEMENT SUBNET NACL
########################################################################
# Purpose: Restrict administrative access to trusted sources only
# Allow:  SSH from VPC (bastion pattern), HTTPS out for updates
# Deny:   Direct SSH from Internet, DB ports
# Note:   In production, replace VPC CIDR SSH rules with VPN CIDR
########################################################################

# resource "aws_network_acl" "mgmt" {
#   vpc_id     = aws_vpc.this.id
#   subnet_ids = [for k, v in aws_subnet.mgmt : v.id]
#
#   tags = merge(var.common_tags, {
#     Name = "${var.project_name}-nacl-mgmt"
#     Tier = "mgmt"
#   })
# }

#--- INBOUND: What enters Management subnets ---

# # SSH from within VPC only (bastion-to-bastion or VPN → bastion)
# # Production: Replace vpc_cidr_block with your VPN/corporate CIDR
# resource "aws_network_acl_rule" "mgmt_inbound_ssh_vpc" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 100
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 22
#   to_port        = 22
# }

# # HTTPS from VPC (monitoring dashboards, management consoles)
# resource "aws_network_acl_rule" "mgmt_inbound_https_vpc" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 110
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 443
#   to_port        = 443
# }

# # Monitoring agent ports from VPC (Prometheus scraping, node_exporter)
# resource "aws_network_acl_rule" "mgmt_inbound_monitoring" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 120
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 9090
#   to_port        = 9100
# }

# # Ephemeral return traffic from Internet (NAT GW — package updates)
# resource "aws_network_acl_rule" "mgmt_inbound_ephemeral" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 900
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 1024
#   to_port        = 65535
# }

# # ❌ DENY SSH from Internet (critical — bastion should never be
# # directly reachable from Internet without VPN)
# resource "aws_network_acl_rule" "mgmt_inbound_deny_ssh_internet" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 50
#   egress         = false
#   protocol       = "tcp"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 22
#   to_port        = 22
# }

# # Explicit deny all other inbound
# resource "aws_network_acl_rule" "mgmt_inbound_deny_all" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 32766
#   egress         = false
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }

#--- OUTBOUND: What leaves Management subnets ---

# # SSH to internal hosts (bastion → private instances for debugging)
# resource "aws_network_acl_rule" "mgmt_outbound_ssh_vpc" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 100
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 22
#   to_port        = 22
# }

# # HTTPS to Internet (via NAT — yum/apt updates, AWS CLI, pip install)
# resource "aws_network_acl_rule" "mgmt_outbound_https" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 110
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 443
#   to_port        = 443
# }

# # HTTP to Internet (some package repos still use HTTP)
# resource "aws_network_acl_rule" "mgmt_outbound_http" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 120
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 80
#   to_port        = 80
# }

# # Postgres to Data tier (DB admin access from bastion)
# resource "aws_network_acl_rule" "mgmt_outbound_postgres" {
#   for_each = local.az_map
#
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 200 + index(keys(local.az_map), each.key)
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.data_cidrs[each.key]
#   from_port      = 5432
#   to_port        = 5432
# }

# # Ephemeral ports — response traffic back to VPC
# resource "aws_network_acl_rule" "mgmt_outbound_ephemeral_vpc" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 900
#   egress         = true
#   protocol       = "tcp"
#   rule_action    = "allow"
#   cidr_block     = local.vpc_cidr_block
#   from_port      = 1024
#   to_port        = 65535
# }

# # Explicit deny all other outbound
# resource "aws_network_acl_rule" "mgmt_outbound_deny_all" {
#   network_acl_id = aws_network_acl.mgmt.id
#   rule_number    = 32766
#   egress         = true
#   protocol       = "-1"
#   rule_action    = "deny"
#   cidr_block     = "0.0.0.0/0"
#   from_port      = 0
#   to_port        = 0
# }
