/**
 * Copyright 2023 Ashes
 *
 * NCC Hub Module - Main Configuration
 *
 * A Network Connectivity Center hub with a preset connectivity topology, the
 * opt-in alternative to hub-and-spoke VPC peering. STAR lets every edge spoke
 * reach the center group but not other edge spokes; MESH lets every spoke reach
 * every other spoke. The topology is immutable: changing it replaces the hub,
 * which first requires deleting every spoke attached to it.
 *
 * The hub's groups are created by the service (STAR: center + edge; MESH:
 * default) and referenced by ID (<hub id>/groups/<name>). The one exception is
 * opt-in: with auto_accept_projects set, the spoke group (edge, or default on
 * MESH) is adopted by name to manage its auto-accept list, so spokes from those
 * projects join without a manual accept. google_network_connectivity_group only
 * accepts the service-created names and its create PATCHes the existing group,
 * so there is nothing to import.
 */

locals {
  # Groups the service pre-creates for each preset topology.
  group_names = var.preset_topology == "STAR" ? ["center", "edge"] : ["default"]
  spoke_group = var.preset_topology == "STAR" ? "edge" : "default"
}

resource "google_network_connectivity_hub" "this" {
  project     = var.project_id
  name        = var.name
  description = var.description
  labels      = var.labels

  policy_mode     = "PRESET"
  preset_topology = var.preset_topology
  export_psc      = var.export_psc
}

# Spoke group auto-accept (opt-in). Spokes in another project than the hub are
# otherwise held for review until the hub admin accepts them.
resource "google_network_connectivity_group" "spoke" {
  count = length(var.auto_accept_projects) > 0 ? 1 : 0

  project     = var.project_id
  hub         = google_network_connectivity_hub.this.id
  name        = local.spoke_group
  description = "Spoke group of ${var.name}, with auto-accept for the landing-zone spoke projects"
  labels      = var.labels

  auto_accept {
    auto_accept_projects = var.auto_accept_projects
  }
}
