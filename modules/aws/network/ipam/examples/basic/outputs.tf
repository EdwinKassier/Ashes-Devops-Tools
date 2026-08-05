output "ipam_id" {
  description = "The ID of the IPAM created by the module."
  value       = module.ipam.ipam_id
}

output "regional_pool_ids" {
  description = "Map of region to regional IPAM pool ID."
  value       = module.ipam.regional_pool_ids
}
