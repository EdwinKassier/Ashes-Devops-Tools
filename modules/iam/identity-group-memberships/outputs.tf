output "membership_ids" {
  description = "Map keyed by \"<group_id>-<member_id>\" to the membership resource ID."
  value       = { for k, v in google_cloud_identity_group_membership.membership : k => v.id }
}

output "membership_names" {
  description = "Map keyed by \"<group_id>-<member_id>\" to the membership resource name."
  value       = { for k, v in google_cloud_identity_group_membership.membership : k => v.name }
}
