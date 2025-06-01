output "memberships" {
  description = "Map of created group memberships with their details"
  value       = google_cloud_identity_group_membership.membership
  sensitive   = false
}
