output "tag_keys" {
  description = "Tag key resources keyed by short name"
  value       = module.resource_tags.tag_keys
}

output "tag_values" {
  description = "Tag value resources keyed by 'key/value'"
  value       = module.resource_tags.tag_values
}
