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
 * default). They are referenced by ID (<hub id>/groups/<name>), never managed
 * here, so this module never fights the service over them.
 */

locals {
  # Groups the service pre-creates for each preset topology.
  group_names = var.preset_topology == "STAR" ? ["center", "edge"] : ["default"]
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
