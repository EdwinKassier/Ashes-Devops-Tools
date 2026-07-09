output "tgw_id" {
  description = "The ID of the transit gateway created by the module."
  value       = module.transit_gateway.tgw_id
}

output "route_table_ids" {
  description = "Map of segment name to transit gateway route table ID."
  value       = module.transit_gateway.route_table_ids
}

output "attachment_ids" {
  description = "Map of attachment name to transit gateway VPC attachment ID."
  value       = module.transit_gateway.attachment_ids
}
