/**
 * Copyright 2023 Ashes
 *
 * VPC Peering Module - Main Configuration
 */

locals {
  peer_project = coalesce(var.peer_project_id, var.project_id)
}

# Primary peering connection (local -> peer)
resource "google_compute_network_peering" "peering" {
  name         = var.peering_name
  network      = var.network
  peer_network = var.peer_network

  export_custom_routes                = var.export_custom_routes
  import_custom_routes                = var.import_custom_routes
  export_subnet_routes_with_public_ip = var.export_subnet_routes_with_public_ip
  import_subnet_routes_with_public_ip = var.import_subnet_routes_with_public_ip
  stack_type                          = var.stack_type
}

# Reverse peering connection (peer -> local) for bi-directional connectivity
resource "google_compute_network_peering" "reverse_peering" {
  count = var.create_reverse_peering ? 1 : 0

  name         = "${var.peering_name}-reverse"
  network      = var.peer_network
  peer_network = var.network

  export_custom_routes                = var.import_custom_routes # Invert for reverse
  import_custom_routes                = var.export_custom_routes # Invert for reverse
  export_subnet_routes_with_public_ip = var.import_subnet_routes_with_public_ip
  import_subnet_routes_with_public_ip = var.export_subnet_routes_with_public_ip
  stack_type                          = var.stack_type

  depends_on = [google_compute_network_peering.peering]
}
