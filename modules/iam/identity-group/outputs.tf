output "identity_groups" {
  description = "Map of created identity groups with their details"
  value       = google_cloud_identity_group.cloud_identity_group
  sensitive   = false
}
