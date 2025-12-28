output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
}

output "organization_id" {
  description = "Organization ID"
  value       = module.organization.organization_id
}

output "tags" {
  description = "Tag Keys and Values"
  value       = module.tags.tag_keys
}
