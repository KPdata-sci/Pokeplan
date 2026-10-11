output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "ecr_repository_urls" {
  value = module.compute.ecr_repository_urls
}

output "deploy_role_arn" {
  description = "Put this in the GitHub Actions workflow (aws-actions/configure-aws-credentials)."
  value       = module.iam.deploy_role_arn
}

output "event_bus_name" {
  value = module.events.bus_name
}

output "buckets" {
  value = module.storage.bucket_names
}
