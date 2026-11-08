output "repository_urls" {
  description = "Map of repository name to its registry URL (for docker push/pull)."
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "Map of repository name to its ARN."
  value       = module.ecr.repository_arns
}
