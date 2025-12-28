/**
 * Copyright 2023 Ashes
 *
 * Cloud Interconnect Module - Main Configuration
 * 
 * Creates Dedicated or Partner Interconnect attachments (VLANs) for
 * high-bandwidth, low-latency connectivity to on-premises networks.
 */

locals {
  router_name = var.create_router ? google_compute_router.router[0].name : var.router_name
}

# -----------------------------------------------------------------------------
# CLOUD ROUTER (if not provided)
# -----------------------------------------------------------------------------

resource "google_compute_router" "router" {
  count = var.create_router ? 1 : 0

  project = var.project_id
  name    = var.router_name
  network = var.network
  region  = var.region

  bgp {
    asn               = var.router_asn
    advertise_mode    = length(var.advertised_ip_ranges) > 0 ? "CUSTOM" : "DEFAULT"
    advertised_groups = var.advertised_groups

    dynamic "advertised_ip_ranges" {
      for_each = var.advertised_ip_ranges
      content {
        range       = advertised_ip_ranges.value.range
        description = try(advertised_ip_ranges.value.description, null)
      }
    }
  }
}

# -----------------------------------------------------------------------------
# DEDICATED INTERCONNECT ATTACHMENT (VLAN)
# -----------------------------------------------------------------------------

resource "google_compute_interconnect_attachment" "dedicated" {
  count = var.interconnect_type == "DEDICATED" ? 1 : 0

  project = var.project_id
  name    = var.attachment_name
  region  = var.region
  router  = local.router_name
  type    = "DEDICATED"

  interconnect      = var.interconnect_self_link
  vlan_tag8021q     = var.vlan_tag
  bandwidth         = var.bandwidth
  candidate_subnets = var.candidate_subnets
  mtu               = var.mtu
  admin_enabled     = var.admin_enabled
  encryption        = var.encryption

  description = var.description
}

# -----------------------------------------------------------------------------
# PARTNER INTERCONNECT ATTACHMENT (VLAN)
# -----------------------------------------------------------------------------

resource "google_compute_interconnect_attachment" "partner" {
  count = var.interconnect_type == "PARTNER" ? 1 : 0

  project = var.project_id
  name    = var.attachment_name
  region  = var.region
  router  = local.router_name
  type    = "PARTNER"

  edge_availability_domain = var.edge_availability_domain
  mtu                      = var.mtu
  admin_enabled            = var.admin_enabled
  encryption               = var.encryption

  description = var.description
}

locals {
  attachment = var.interconnect_type == "DEDICATED" ? (
    length(google_compute_interconnect_attachment.dedicated) > 0 ?
    google_compute_interconnect_attachment.dedicated[0] : null
    ) : (
    length(google_compute_interconnect_attachment.partner) > 0 ?
    google_compute_interconnect_attachment.partner[0] : null
  )
}

# -----------------------------------------------------------------------------
# ROUTER INTERFACE (binds VLAN to router)
# -----------------------------------------------------------------------------

resource "google_compute_router_interface" "interface" {
  count = local.attachment != null && var.create_bgp_peer ? 1 : 0

  project                 = var.project_id
  name                    = "${var.attachment_name}-interface"
  router                  = local.router_name
  region                  = var.region
  ip_range                = var.interface_ip_range
  interconnect_attachment = local.attachment.self_link
}

# -----------------------------------------------------------------------------
# BGP PEER (establishes BGP session with on-prem router)
# -----------------------------------------------------------------------------

resource "google_compute_router_peer" "peer" {
  count = local.attachment != null && var.create_bgp_peer ? 1 : 0

  project                   = var.project_id
  name                      = "${var.attachment_name}-peer"
  router                    = local.router_name
  region                    = var.region
  peer_ip_address           = var.peer_ip_address
  peer_asn                  = var.peer_asn
  advertised_route_priority = var.advertised_route_priority
  interface                 = google_compute_router_interface.interface[0].name

  dynamic "bfd" {
    for_each = var.enable_bfd ? [1] : []
    content {
      session_initialization_mode = var.bfd_session_initialization_mode
      min_transmit_interval       = var.bfd_min_transmit_interval
      min_receive_interval        = var.bfd_min_receive_interval
      multiplier                  = var.bfd_multiplier
    }
  }
}
