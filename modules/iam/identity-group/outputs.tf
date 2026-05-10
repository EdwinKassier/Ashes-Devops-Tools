output "group_id" {
  description = "The unique resource ID of the Cloud Identity group (e.g. groups/123456789)."
  value       = google_cloud_identity_group.cloud_identity_group.id
}

output "group_name" {
  description = "The resource name of the Cloud Identity group (e.g. groups/123456789)."
  value       = google_cloud_identity_group.cloud_identity_group.name
}

output "display_name" {
  description = "The display name of the Cloud Identity group."
  value       = google_cloud_identity_group.cloud_identity_group.display_name
}

output "group_key" {
  description = "The email address / group key that identifies this group."
  value       = google_cloud_identity_group.cloud_identity_group.group_key[0].id
}
