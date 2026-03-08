output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
}

output "organization_id" {
  description = "Organization ID"
  value       = module.organization.organization_id
}

output "tag_keys" {
  description = "Tag keys available to downstream consumers"
  value       = module.tags.tag_keys
}

output "tag_value_ids" {
  description = "Tag values available to downstream consumers"
  value       = module.tags.tag_values
}

output "tags" {
  description = "Deprecated alias for downstream tag values"
  value       = module.tags.tag_values
}
