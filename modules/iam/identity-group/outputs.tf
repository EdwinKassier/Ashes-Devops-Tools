output "group_ids" {
  description = "Map of group key → unique resource ID (e.g. groups/123456789), keyed by the group's email/id."
  value       = { for k, v in google_cloud_identity_group.cloud_identity_group : k => v.id }
}

output "group_names" {
  description = "Map of group key → resource name (e.g. groups/123456789), keyed by the group's email/id."
  value       = { for k, v in google_cloud_identity_group.cloud_identity_group : k => v.name }
}

output "display_names" {
  description = "Map of group key → display name, keyed by the group's email/id."
  value       = { for k, v in google_cloud_identity_group.cloud_identity_group : k => v.display_name }
}

output "group_keys" {
  description = "Map of group key → email address that identifies each group, keyed by the group's email/id."
  value       = { for k, v in google_cloud_identity_group.cloud_identity_group : k => v.group_key[0].id }
}
