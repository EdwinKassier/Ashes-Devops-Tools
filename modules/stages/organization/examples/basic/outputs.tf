output "organization_id" {
  description = "The GCP organization ID"
  value       = module.organization.organization_id
}

output "environment_folders" {
  description = "Map of environment name to folder resource"
  value       = module.organization.folders
}
