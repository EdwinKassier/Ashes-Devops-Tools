output "repository_ids" {
  description = "Map of repository names to their IDs"
  value       = { for k, v in google_artifact_registry_repository.repo : k => v.id }
}

output "repository_names" {
  description = "Map of repository names to their full resource names"
  value       = { for k, v in google_artifact_registry_repository.repo : k => v.name }
}

output "repository_urls" {
  description = "Map of repository names to their Docker registry URLs"
  value = {
    for k, v in google_artifact_registry_repository.repo : k => "${var.region}-docker.pkg.dev/${var.project_id}/${k}"
  }
}
