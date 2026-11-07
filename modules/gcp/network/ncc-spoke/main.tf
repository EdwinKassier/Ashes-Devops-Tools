/**
 * Copyright 2023 Ashes
 *
 * NCC Spoke Module - Main Configuration
 *
 * One Network Connectivity Center spoke attached to a hub group, linking
 * either a VPC network (global) or a set of HA VPN tunnels (regional), plus
 * optional producer VPC spokes for the VPC's Private Service Access peerings.
 *
 * Producer spokes read hub and group from the consumer VPC spoke, so they
 * always join the same group and are created only after it: NCC rejects a
 * producer VPC spoke whose consumer VPC is not already a spoke.
 *
 * NCC also rejects a VPC spoke whose VPC is still peered with another VPC
 * spoke; see docs/runbooks/gcp-peering-to-ncc-migration.md.
 */

locals {
  # Empty range lists go to the API as null, not [], so the plan stays stable.
  vpc = var.linked_vpc_network == null ? null : {
    uri                   = var.linked_vpc_network.uri
    include_export_ranges = length(var.linked_vpc_network.include_export_ranges) > 0 ? var.linked_vpc_network.include_export_ranges : null
    exclude_export_ranges = length(var.linked_vpc_network.exclude_export_ranges) > 0 ? var.linked_vpc_network.exclude_export_ranges : null
  }
  vpn = var.linked_vpn_tunnels == null ? null : {
    uris                       = var.linked_vpn_tunnels.uris
    site_to_site_data_transfer = var.linked_vpn_tunnels.site_to_site_data_transfer
    include_import_ranges      = length(var.linked_vpn_tunnels.include_import_ranges) > 0 ? var.linked_vpn_tunnels.include_import_ranges : null
  }
}

resource "google_network_connectivity_spoke" "this" {
  project     = var.project_id
  name        = var.name
  location    = var.location
  description = var.description
  labels      = var.labels

  hub   = var.hub_id
  group = "${var.hub_id}/groups/${var.group}"

  dynamic "linked_vpc_network" {
    for_each = local.vpc == null ? [] : [local.vpc]
    content {
      uri                   = linked_vpc_network.value.uri
      include_export_ranges = linked_vpc_network.value.include_export_ranges
      exclude_export_ranges = linked_vpc_network.value.exclude_export_ranges
    }
  }

  dynamic "linked_vpn_tunnels" {
    for_each = local.vpn == null ? [] : [local.vpn]
    content {
      uris                       = linked_vpn_tunnels.value.uris
      site_to_site_data_transfer = linked_vpn_tunnels.value.site_to_site_data_transfer
      include_import_ranges      = linked_vpn_tunnels.value.include_import_ranges
    }
  }
}

# Producer VPC spokes (Private Service Access): same hub and group as the
# consumer VPC spoke above, read from it so the consumer spoke exists first.
resource "google_network_connectivity_spoke" "producer" {
  for_each = var.linked_vpc_network == null ? {} : var.producer_vpc_networks

  project     = var.project_id
  name        = "${var.name}-${each.key}"
  location    = "global"
  description = "Producer VPC spoke for ${each.key} (Private Service Access) of ${var.name}"
  labels      = var.labels

  hub   = google_network_connectivity_spoke.this.hub
  group = google_network_connectivity_spoke.this.group

  linked_producer_vpc_network {
    network               = each.value.network
    peering               = each.value.peering
    include_export_ranges = length(each.value.include_export_ranges) > 0 ? each.value.include_export_ranges : null
    exclude_export_ranges = length(each.value.exclude_export_ranges) > 0 ? each.value.exclude_export_ranges : null
  }

  depends_on = [google_network_connectivity_spoke.this]
}
