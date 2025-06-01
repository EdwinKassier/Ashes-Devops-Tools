# Service URLs
output "service_urls" {
  description = "Map of service names to their URLs"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.uri }
}

# Service statuses
output "service_statuses" {
  description = "Map of service names to their statuses"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.conditions[0].status }
}

# Service UIDs
output "service_uids" {
  description = "Map of service names to their UIDs"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.uid }
}

# Service etags
output "service_etags" {
  description = "Map of service names to their etags"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.etag }
}

# Service generation
output "service_generations" {
  description = "Map of service names to their generations"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.generation }
}

# Service latest ready revisions
output "latest_ready_revisions" {
  description = "Map of service names to their latest ready revisions"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.latest_ready_revision }
}

# Service traffic statuses
output "traffic_statuses" {
  description = "Map of service names to their traffic statuses"
  value       = { for k, v in google_cloud_run_v2_service.service : k => v.traffic_statuses }
}

# IAM policies
output "iam_policies" {
  description = "Map of service names to their IAM policies"
  value       = { for k, v in google_cloud_run_v2_service.service : k => google_cloud_run_service_iam_binding.no_public[k].etag }
}