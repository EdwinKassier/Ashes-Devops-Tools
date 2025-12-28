output "tag_keys" {
  description = "Map of Tag Key Short Names to their Resource Names (IDs)"
  value       = { for k, v in google_tags_tag_key.keys : k => v.name }
}

output "tag_values" {
  description = "Map of Tag Value Short Names to their Resource Names (IDs)"
  value       = { for k, v in google_tags_tag_value.values : k => v.name }
}
