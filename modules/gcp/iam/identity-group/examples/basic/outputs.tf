output "group_ids" {
  description = "Map of group email to resource ID for each created group."
  value       = module.gcp_groups.group_ids
}

output "group_names" {
  description = "Map of group email to resource name for each created group."
  value       = module.gcp_groups.group_names
}
