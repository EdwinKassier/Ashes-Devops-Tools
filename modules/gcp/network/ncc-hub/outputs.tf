/**
 * Copyright 2023 Ashes
 *
 * NCC Hub Module - Outputs
 */

output "id" {
  description = "The hub ID (projects/<project>/locations/global/hubs/<name>); pass it to network/ncc-spoke hub_id."
  value       = google_network_connectivity_hub.this.id
}

output "name" {
  description = "The hub name."
  value       = google_network_connectivity_hub.this.name
}

output "preset_topology" {
  description = "The hub's preset topology (STAR or MESH)."
  value       = google_network_connectivity_hub.this.preset_topology
}

output "group_ids" {
  description = "IDs of the service-created groups, keyed by group name (STAR: center, edge; MESH: default)."
  value       = { for g in local.group_names : g => "${google_network_connectivity_hub.this.id}/groups/${g}" }
}

output "spoke_group" {
  description = "The group name a spoke VPC joins: edge for STAR, default for MESH."
  value       = local.spoke_group
}

output "center_group" {
  description = "The group name the hub VPC joins: center for STAR, default for MESH."
  value       = var.preset_topology == "STAR" ? "center" : "default"
}

output "auto_accept_projects" {
  description = "Projects whose spokes the spoke group accepts automatically (empty = the group is not managed)."
  value       = var.auto_accept_projects
}
