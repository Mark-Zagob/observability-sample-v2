#--------------------------------------------------------------
# ECS Cluster Module — Outputs
#--------------------------------------------------------------

output "cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "namespace_id" {
  description = "Cloud Map namespace ID (for service discovery registration)"
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_arn" {
  description = "Cloud Map namespace ARN"
  value       = aws_service_discovery_private_dns_namespace.this.arn
}

output "namespace_name" {
  description = "Cloud Map namespace name (e.g., ecommerce.local)"
  value       = aws_service_discovery_private_dns_namespace.this.name
}
