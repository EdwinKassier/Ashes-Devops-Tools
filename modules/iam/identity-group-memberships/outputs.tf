output "membership_ids" {
  description = "Map of member email to membership resource ID."
  value       = { for k, v in google_cloud_identity_group_membership.membership : k => v.id }
}

output "membership_names" {
  description = "Map of member email to membership resource name."
  value       = { for k, v in google_cloud_identity_group_membership.membership : k => v.name }
}
