output "resource_policy_self_links" {
  description = "Schedule name to resource policy self_link; attach these to disks."
  value       = module.backup.resource_policy_self_links
}

output "schedule_names" {
  description = "Names of the snapshot-schedule policies."
  value       = module.backup.schedule_names
}
