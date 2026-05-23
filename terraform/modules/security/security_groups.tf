#--------------------------------------------------------------
# Security Groups — Defense-in-Depth Layer 2
#--------------------------------------------------------------
# NACLs (network module) = subnet-level, stateless, coarse deny
# SGs (this file)        = instance-level, stateful, fine allow
#
# Chain: ALB → App → Data/EFS/Observability
#        Bastion → App + Data (admin access)
#
# Pattern: source_security_group_id (not CIDRs) for inter-tier
#          rules. This ensures traffic only flows between
#          resources that are members of the correct SG.
#
# Reference: AWS Well-Architected SEC05-BP03
#--------------------------------------------------------------


########################################################################
# 1. ALB Security Group
########################################################################
# Purpose: Internet-facing load balancer
# Inbound:  80/443 from Internet (web traffic)
# Outbound: app_port to App SG (health checks + forwarding)
########################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "ALB - Allow HTTP/HTTPS from Internet, forward to App tier"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-alb"
    Tier = "public"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- ALB Inbound ---

resource "aws_security_group_rule" "alb_ingress_http" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "HTTP from Internet"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "HTTPS from Internet"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- ALB Outbound ---

resource "aws_security_group_rule" "alb_egress_to_app" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  description              = "Forward traffic to App containers"
  protocol                 = "tcp"
  from_port                = var.app_port
  to_port                  = var.app_port
  source_security_group_id = aws_security_group.application.id
}

resource "aws_security_group_rule" "alb_egress_to_app_health" {
  count = var.app_health_check_port > 0 && var.app_health_check_port != var.app_port ? 1 : 0

  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  description              = "Health check to App containers"
  protocol                 = "tcp"
  from_port                = var.app_health_check_port
  to_port                  = var.app_health_check_port
  source_security_group_id = aws_security_group.application.id
}


########################################################################
# 2. Application Security Group
########################################################################
# Purpose: ECS Fargate containers (app tier)
# Inbound:  app_port from ALB SG, SSH from Bastion SG
# Outbound: DB ports to Data SG, 443 to Internet (APIs),
#           2049 to EFS SG, monitoring ports to Observability SG
########################################################################

resource "aws_security_group" "application" {
  name_prefix = "${var.project_name}-app-"
  description = "Application containers - Receive from ALB, connect to Data/EFS"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-app"
    Tier = "private"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- App Inbound ---

resource "aws_security_group_rule" "app_ingress_from_alb" {
  security_group_id        = aws_security_group.application.id
  type                     = "ingress"
  description              = "App port from ALB"
  protocol                 = "tcp"
  from_port                = var.app_port
  to_port                  = var.app_port
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "app_ingress_health_from_alb" {
  count = var.app_health_check_port > 0 && var.app_health_check_port != var.app_port ? 1 : 0

  security_group_id        = aws_security_group.application.id
  type                     = "ingress"
  description              = "Health check port from ALB"
  protocol                 = "tcp"
  from_port                = var.app_health_check_port
  to_port                  = var.app_health_check_port
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "app_ingress_ssh_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id        = aws_security_group.application.id
  type                     = "ingress"
  description              = "SSH from Bastion for debugging"
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  source_security_group_id = aws_security_group.bastion[0].id
}

# --- App Outbound ---

resource "aws_security_group_rule" "app_egress_to_data" {
  for_each = var.db_ports

  security_group_id        = aws_security_group.application.id
  type                     = "egress"
  description              = "${each.key} to Data tier (port ${each.value})"
  protocol                 = "tcp"
  from_port                = each.value
  to_port                  = each.value
  source_security_group_id = aws_security_group.data.id
}

resource "aws_security_group_rule" "app_egress_to_efs" {
  security_group_id        = aws_security_group.application.id
  type                     = "egress"
  description              = "NFS to EFS"
  protocol                 = "tcp"
  from_port                = 2049
  to_port                  = 2049
  source_security_group_id = aws_security_group.efs.id
}

resource "aws_security_group_rule" "app_egress_https" {
  security_group_id = aws_security_group.application.id
  type              = "egress"
  description       = "HTTPS to Internet (APIs, package managers, AWS services)"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app_egress_http" {
  security_group_id = aws_security_group.application.id
  type              = "egress"
  description       = "HTTP to Internet (redirects, package repos)"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "app_egress_dns_tcp" {
  security_group_id = aws_security_group.application.id
  type              = "egress"
  description       = "DNS resolution (TCP)"
  protocol          = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_blocks       = [var.vpc_cidr_block]
}

resource "aws_security_group_rule" "app_egress_dns_udp" {
  security_group_id = aws_security_group.application.id
  type              = "egress"
  description       = "DNS resolution (UDP)"
  protocol          = "udp"
  from_port         = 53
  to_port           = 53
  cidr_blocks       = [var.vpc_cidr_block]
}

# OTLP telemetry to Observability tier
resource "aws_security_group_rule" "app_egress_otlp_grpc" {
  security_group_id        = aws_security_group.application.id
  type                     = "egress"
  description              = "OTLP gRPC to Observability (traces, metrics)"
  protocol                 = "tcp"
  from_port                = 4317
  to_port                  = 4317
  source_security_group_id = aws_security_group.observability.id
}

resource "aws_security_group_rule" "app_egress_otlp_http" {
  security_group_id        = aws_security_group.application.id
  type                     = "egress"
  description              = "OTLP HTTP to Observability (logs)"
  protocol                 = "tcp"
  from_port                = 4318
  to_port                  = 4318
  source_security_group_id = aws_security_group.observability.id
}


########################################################################
# 3. Data Security Group
########################################################################
# Purpose: RDS, ElastiCache (Redis), MSK (Kafka)
# Inbound:  DB ports from App SG + Bastion SG only
# Outbound: Ephemeral responses only (stateful, no explicit egress needed)
# Note:     This is the MOST restrictive SG — no Internet access
########################################################################

resource "aws_security_group" "data" {
  name_prefix = "${var.project_name}-data-"
  description = "Data tier (RDS/Redis/Kafka) - Accept ONLY from App and Bastion SGs"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-data"
    Tier = "data"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Data Inbound from App ---

resource "aws_security_group_rule" "data_ingress_from_app" {
  for_each = var.db_ports

  security_group_id        = aws_security_group.data.id
  type                     = "ingress"
  description              = "${each.key} from App tier (port ${each.value})"
  protocol                 = "tcp"
  from_port                = each.value
  to_port                  = each.value
  source_security_group_id = aws_security_group.application.id
}

# --- Data Inbound from Bastion (admin access) ---

resource "aws_security_group_rule" "data_ingress_from_bastion" {
  for_each = var.enable_bastion ? var.db_ports : {}

  security_group_id        = aws_security_group.data.id
  type                     = "ingress"
  description              = "${each.key} from Bastion (admin, port ${each.value})"
  protocol                 = "tcp"
  from_port                = each.value
  to_port                  = each.value
  source_security_group_id = aws_security_group.bastion[0].id
}

# --- Data Outbound ---
# SGs are stateful: response traffic is automatically allowed.
# No explicit egress needed for DB servers — they should NEVER
# initiate outbound connections.
#
# IMPORTANT: When using separate aws_security_group_rule resources
# (not inline), AWS removes the default allow-all egress rule.
# So we only allow ephemeral port responses back to App and Bastion SGs.

resource "aws_security_group_rule" "data_egress_response_to_app" {
  security_group_id        = aws_security_group.data.id
  type                     = "egress"
  description              = "Ephemeral port responses to App tier"
  protocol                 = "tcp"
  from_port                = 1024
  to_port                  = 65535
  source_security_group_id = aws_security_group.application.id
}

resource "aws_security_group_rule" "data_egress_response_to_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id        = aws_security_group.data.id
  type                     = "egress"
  description              = "Ephemeral port responses to Bastion (admin queries)"
  protocol                 = "tcp"
  from_port                = 1024
  to_port                  = 65535
  source_security_group_id = aws_security_group.bastion[0].id
}


########################################################################
# 4. EFS Security Group
########################################################################
# Purpose: Elastic File System mount targets
# Inbound:  NFS (2049) from App SG only
# Outbound: Stateful responses only
########################################################################

resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-efs-"
  description = "EFS mount targets - NFS from App tier only"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-efs"
    Tier = "data"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "efs_ingress_from_app" {
  security_group_id        = aws_security_group.efs.id
  type                     = "ingress"
  description              = "NFS from App containers"
  protocol                 = "tcp"
  from_port                = 2049
  to_port                  = 2049
  source_security_group_id = aws_security_group.application.id
}

resource "aws_security_group_rule" "efs_egress_to_app" {
  security_group_id        = aws_security_group.efs.id
  type                     = "egress"
  description              = "NFS responses to App containers"
  protocol                 = "tcp"
  from_port                = 1024
  to_port                  = 65535
  source_security_group_id = aws_security_group.application.id
}


########################################################################
# 5. Observability Security Group
########################################################################
# Purpose: Prometheus, Grafana, Loki, Tempo, exporters
# Inbound:  Monitoring ports from VPC (scraping, dashboards)
# Outbound: HTTPS to Internet (alerting, plugin downloads)
########################################################################

resource "aws_security_group" "observability" {
  name_prefix = "${var.project_name}-obs-"
  description = "Observability stack (Prometheus/Grafana/Loki/Tempo)"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-observability"
    Tier = "private"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Observability Inbound ---

resource "aws_security_group_rule" "obs_ingress_from_vpc" {
  for_each = var.monitoring_ports

  security_group_id = aws_security_group.observability.id
  type              = "ingress"
  description       = "${each.key} from VPC (port ${each.value})"
  protocol          = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_blocks       = [var.vpc_cidr_block]
}

# OTLP gRPC from App containers (OpenTelemetry)
resource "aws_security_group_rule" "obs_ingress_otlp_from_app" {
  security_group_id        = aws_security_group.observability.id
  type                     = "ingress"
  description              = "OTLP gRPC from App containers"
  protocol                 = "tcp"
  from_port                = 4317
  to_port                  = 4317
  source_security_group_id = aws_security_group.application.id
}

# OTLP HTTP from App containers
resource "aws_security_group_rule" "obs_ingress_otlp_http_from_app" {
  security_group_id        = aws_security_group.observability.id
  type                     = "ingress"
  description              = "OTLP HTTP from App containers"
  protocol                 = "tcp"
  from_port                = 4318
  to_port                  = 4318
  source_security_group_id = aws_security_group.application.id
}

# --- Observability Outbound ---

resource "aws_security_group_rule" "obs_egress_https" {
  security_group_id = aws_security_group.observability.id
  type              = "egress"
  description       = "HTTPS to Internet (alerts, plugins)"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}

# Scrape app metrics
resource "aws_security_group_rule" "obs_egress_scrape_app" {
  security_group_id        = aws_security_group.observability.id
  type                     = "egress"
  description              = "Prometheus scrape App containers"
  protocol                 = "tcp"
  from_port                = var.app_port
  to_port                  = var.app_port
  source_security_group_id = aws_security_group.application.id
}

# Scrape node_exporter on internal hosts
resource "aws_security_group_rule" "obs_egress_scrape_exporters" {
  security_group_id = aws_security_group.observability.id
  type              = "egress"
  description       = "Scrape node/service exporters within VPC"
  protocol          = "tcp"
  from_port         = 9090
  to_port           = 9100
  cidr_blocks       = [var.vpc_cidr_block]
}


########################################################################
# 6. Bastion Security Group (conditional)
########################################################################
# Purpose: Jump host / SSH gateway for admin access
# Inbound:  SSH from allowed CIDRs only
# Outbound: SSH to App/Data, HTTPS for updates, SSM agent
# Note:     Created only when enable_bastion = true
########################################################################

resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name_prefix = "${var.project_name}-bastion-"
  description = "Bastion host - SSH from trusted CIDRs, access internal resources"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-sg-bastion"
    Tier = "mgmt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Bastion Inbound ---

resource "aws_security_group_rule" "bastion_ingress_ssh" {
  count = var.enable_bastion && length(var.allowed_ssh_cidrs) > 0 ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "ingress"
  description       = "SSH from trusted CIDRs"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = var.allowed_ssh_cidrs
}

# --- Bastion Outbound ---

resource "aws_security_group_rule" "bastion_egress_ssh_to_vpc" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "egress"
  description       = "SSH to internal hosts for debugging"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = [var.vpc_cidr_block]
}

resource "aws_security_group_rule" "bastion_egress_https" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "egress"
  description       = "HTTPS to Internet (yum/apt updates, AWS CLI, SSM agent)"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "bastion_egress_http" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "egress"
  description       = "HTTP to Internet (package repos)"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "bastion_egress_db_ports" {
  for_each = var.enable_bastion ? var.db_ports : {}

  security_group_id        = aws_security_group.bastion[0].id
  type                     = "egress"
  description              = "${each.key} to Data tier (admin, port ${each.value})"
  protocol                 = "tcp"
  from_port                = each.value
  to_port                  = each.value
  source_security_group_id = aws_security_group.data.id
}

resource "aws_security_group_rule" "bastion_egress_dns_tcp" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "egress"
  description       = "DNS resolution (TCP)"
  protocol          = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_blocks       = [var.vpc_cidr_block]
}

resource "aws_security_group_rule" "bastion_egress_dns_udp" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  type              = "egress"
  description       = "DNS resolution (UDP)"
  protocol          = "udp"
  from_port         = 53
  to_port           = 53
  cidr_blocks       = [var.vpc_cidr_block]
}
