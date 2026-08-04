output "registry_urls" {
  description = "Map of repository name to push/pull URL"
  value       = module.registries.repository_urls
}
