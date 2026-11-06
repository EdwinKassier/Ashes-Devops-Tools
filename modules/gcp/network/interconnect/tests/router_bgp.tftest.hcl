# Regression test: advertised_groups must be unset when advertise_mode is DEFAULT.
# GCP rejects advertised_groups unless advertise_mode = "CUSTOM".
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "us-central1"
  network         = "projects/mock-project/global/networks/mock-vpc"
  attachment_name = "test-attachment"
  router_name     = "test-router"
}

run "default_mode_omits_advertised_groups" {
  command = plan

  # No advertised_ip_ranges → advertise_mode is DEFAULT → advertised_groups must be null/empty.
  assert {
    condition     = try(length(google_compute_router.router[0].bgp[0].advertised_groups), 0) == 0
    error_message = "advertised_groups must be unset when advertise_mode is DEFAULT"
  }
}

# --- Behavioural plan assertions (attachment type switch, BGP, BFD) ----------

run "partner_defaults" {
  command = plan

  variables {
    interface_ip_range = "169.254.10.1/29"
    peer_ip_address    = "169.254.10.2"
  }

  assert {
    condition     = google_compute_router.router[0].bgp[0].advertise_mode == "DEFAULT" && google_compute_router.router[0].bgp[0].asn == 64512
    error_message = "Router BGP must default to advertise_mode DEFAULT with ASN 64512."
  }

  assert {
    condition     = length(google_compute_interconnect_attachment.partner) == 1 && length(google_compute_interconnect_attachment.dedicated) == 0
    error_message = "interconnect_type defaults to PARTNER: exactly one partner and no dedicated attachment."
  }

  assert {
    condition     = google_compute_interconnect_attachment.partner[0].type == "PARTNER" && google_compute_interconnect_attachment.partner[0].edge_availability_domain == "AVAILABILITY_DOMAIN_1"
    error_message = "Partner attachment must be type PARTNER in AVAILABILITY_DOMAIN_1 by default."
  }

  assert {
    condition     = google_compute_interconnect_attachment.partner[0].mtu == "1440" && google_compute_interconnect_attachment.partner[0].admin_enabled == true
    error_message = "Partner attachment must default to MTU 1440 and admin_enabled = true."
  }

  assert {
    condition     = google_compute_interconnect_attachment.partner[0].router == "test-router"
    error_message = "Attachment must bind to the module-created router."
  }

  assert {
    condition     = google_compute_router_interface.interface[0].name == "test-attachment-interface"
    error_message = "Router interface name must be derived as <attachment_name>-interface."
  }

  assert {
    condition     = google_compute_router_peer.peer[0].name == "test-attachment-peer"
    error_message = "BGP peer name must be derived as <attachment_name>-peer."
  }

  assert {
    condition     = google_compute_router_peer.peer[0].peer_asn == 65000 && google_compute_router_peer.peer[0].advertised_route_priority == 100
    error_message = "BGP peer must default to peer ASN 65000 and route priority 100."
  }

  assert {
    condition     = google_compute_router_peer.peer[0].interface == "test-attachment-interface"
    error_message = "BGP peer must bind to the derived router interface."
  }

  assert {
    condition     = length(google_compute_router_peer.peer[0].bfd) == 0
    error_message = "BFD must be disabled by default."
  }
}

run "dedicated_custom_advertisement_and_bfd" {
  command = plan

  variables {
    interconnect_type      = "DEDICATED"
    interconnect_self_link = "https://www.googleapis.com/compute/v1/projects/mock-project/global/interconnects/ic-1"
    vlan_tag               = 100
    interface_ip_range     = "169.254.20.1/29"
    peer_ip_address        = "169.254.20.2"
    advertised_ip_ranges = [
      { range = "10.0.0.0/8", description = "rfc1918" },
    ]
    enable_bfd = true
  }

  assert {
    condition     = length(google_compute_interconnect_attachment.dedicated) == 1 && length(google_compute_interconnect_attachment.partner) == 0
    error_message = "DEDICATED must plan exactly one dedicated and no partner attachment."
  }

  assert {
    condition     = google_compute_interconnect_attachment.dedicated[0].type == "DEDICATED" && google_compute_interconnect_attachment.dedicated[0].bandwidth == "BPS_10G"
    error_message = "Dedicated attachment must be type DEDICATED with default bandwidth BPS_10G."
  }

  assert {
    condition     = google_compute_router.router[0].bgp[0].advertise_mode == "CUSTOM"
    error_message = "Supplying advertised_ip_ranges must switch advertise_mode to CUSTOM."
  }

  assert {
    condition     = google_compute_router.router[0].bgp[0].advertised_groups == tolist(["ALL_SUBNETS"])
    error_message = "CUSTOM mode must advertise the default ALL_SUBNETS group."
  }

  assert {
    condition     = length(google_compute_router.router[0].bgp[0].advertised_ip_ranges) == 1
    error_message = "Each advertised_ip_ranges entry must render one advertised range."
  }

  assert {
    condition     = google_compute_router_peer.peer[0].bfd[0].session_initialization_mode == "ACTIVE" && google_compute_router_peer.peer[0].bfd[0].multiplier == 5
    error_message = "enable_bfd must render a BFD block with ACTIVE mode and multiplier 5."
  }
}

run "existing_router_no_peer" {
  command = plan

  variables {
    create_router   = false
    router_name     = "existing-router"
    create_bgp_peer = false
  }

  assert {
    condition     = length(google_compute_router.router) == 0
    error_message = "create_router = false must not plan a router."
  }

  assert {
    condition     = google_compute_interconnect_attachment.partner[0].router == "existing-router"
    error_message = "Attachment must bind to the supplied existing router."
  }

  assert {
    condition     = length(google_compute_router_interface.interface) == 0 && length(google_compute_router_peer.peer) == 0
    error_message = "create_bgp_peer = false must skip the router interface and BGP peer."
  }
}

run "module_labels_applied" {
  command = plan

  variables {
    labels = { owner = "test" }

  }

  assert {
    condition     = google_compute_interconnect_attachment.partner[0].labels["owner"] == "test"
    error_message = "var.labels must land on the interconnect attachment."
  }
}
