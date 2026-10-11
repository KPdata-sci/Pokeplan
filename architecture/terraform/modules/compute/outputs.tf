output "alb_dns_name" {
  description = "Point metabase.<domain> and dagster.<domain> here (alias records)."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "ecr_repository_urls" {
  value = local.repo
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}
