output "hub_id" {
  description = "The NCC hub ID"
  value       = module.ncc_hub.id
}

output "group_ids" {
  description = "The service-created group IDs"
  value       = module.ncc_hub.group_ids
}
