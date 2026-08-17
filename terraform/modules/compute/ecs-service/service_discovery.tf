#--------------------------------------------------------------
# ECS Service Module — Cloud Map Service Discovery
#--------------------------------------------------------------
# Registers this service in Cloud Map so other services
# can discover it via DNS:
#   http://payment-service.ecommerce.local:5002
#
# ECS automatically registers/deregisters task IPs.
#--------------------------------------------------------------

resource "aws_service_discovery_service" "this" {
  count = var.enable_service_discovery ? 1 : 0

  name = var.service_name

  dns_config {
    namespace_id = var.namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.service_name}"
    Service = var.service_name
  })
}
