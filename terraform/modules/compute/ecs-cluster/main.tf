#--------------------------------------------------------------
# ECS Cluster Module — Cluster + Cloud Map Namespace
#--------------------------------------------------------------
# Deploy once, rarely changes. Shared by all ECS services.
#
# Cloud Map creates private DNS namespace (e.g., ecommerce.local)
# so services can discover each other:
#   payment-service.ecommerce.local → ECS task IP
#   order-service.ecommerce.local   → ECS task IP
#--------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cluster"
  })
}

#--------------------------------------------------------------
# Cloud Map — Private DNS Namespace
#--------------------------------------------------------------
# Creates a private hosted zone in Route 53 (e.g., ecommerce.local)
# ECS services register into this namespace automatically.
# Other services resolve via DNS: http://service-name.ecommerce.local:port
#--------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.namespace_name
  description = "Service discovery for ${var.project_name} ECS services"
  vpc         = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.namespace_name}"
  })
}
