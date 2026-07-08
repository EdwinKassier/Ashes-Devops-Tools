output "repository_ids" {
  description = "Map of repository names to their IDs"
  value       = { for k, v in google_artifact_registry_repository.repo : k => v.id }
}

output "repository_names" {
  description = "Map of repository names to their full resource names"
  value       = { for k, v in google_artifact_registry_repository.repo : k => v.name }
}

output "repository_urls" {
  description = "Map of repository names to their package-registry URLs, built per format (docker/maven/npm/python). Formats without a registry host (APT/YUM/GOOGET/KFP/GENERIC) are omitted."
  value = {
    for k, v in google_artifact_registry_repository.repo :
    k => "${var.region}-${local.ar_hosts[v.format]}.pkg.dev/${var.project_id}/${k}"
    if contains(keys(local.ar_hosts), v.format)
  }
}
