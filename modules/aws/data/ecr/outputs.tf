output "repository_urls" {
  description = "Map of repository name to its registry URL (for docker push/pull)."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository name to its ARN."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_ids" {
  description = "Map of repository name to the registry (account) ID hosting it."
  value       = { for k, v in aws_ecr_repository.this : k => v.registry_id }
}
