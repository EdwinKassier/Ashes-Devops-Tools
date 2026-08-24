output "resource_policy_ids" {
  description = "Map of schedule name to the resource policy ID."
  value       = { for k, v in google_compute_resource_policy.snapshot : k => v.id }
}

output "resource_policy_self_links" {
  description = "Map of schedule name to the resource policy self_link (full resource URL). Attach these to persistent disks via google_compute_disk_resource_policy_attachment."
  value       = { for k, v in google_compute_resource_policy.snapshot : k => v.self_link }
}

output "schedule_names" {
  description = "List of the snapshot-schedule policy names created by this module."
  value       = sort(keys(google_compute_resource_policy.snapshot))
}
