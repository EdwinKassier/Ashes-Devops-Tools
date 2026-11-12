# Resource-assertion tests for the network/vpn module.
# Prior tests only validated inputs; nothing asserted that tunnel_count actually
# creates N tunnels, that IKEv2 is used, or that shared_secret is wired
#. These assert the tunnel wiring on the plan.

mock_provider "google" {}

variables {
  project_id                = "mock-project"
  name                      = "test-vpn"
  network                   = "projects/mock-project/global/networks/mock-vpc"
  region                    = "europe-west1"
  peer_external_gateway_ips = ["203.0.113.1", "203.0.113.2"]
  shared_secret             = "mock-secret"
}

run "creates_tunnels_with_ikev2_and_shared_secret" {
  command = plan

  variables {
    tunnel_count = 2
  }

  assert {
    condition     = length(google_compute_vpn_tunnel.tunnels) == 2
    error_message = "tunnel_count must create exactly that many VPN tunnels."
  }

  assert {
    condition     = alltrue([for t in google_compute_vpn_tunnel.tunnels : t.ike_version == 2])
    error_message = "Every VPN tunnel must use IKEv2."
  }

  assert {
    condition     = alltrue([for t in google_compute_vpn_tunnel.tunnels : t.shared_secret == "mock-secret"])
    error_message = "shared_secret must be wired into every VPN tunnel."
  }
}

run "write_only_secret_never_reaches_the_planned_attribute" {
  command = plan

  variables {
    shared_secret            = null
    shared_secret_wo         = "mock-wo-secret"
    shared_secret_wo_version = 2
  }

  assert {
    condition     = alltrue([for t in google_compute_vpn_tunnel.tunnels : t.shared_secret == null && t.shared_secret_wo_version == "2"])
    error_message = "A write-only secret must leave shared_secret null and carry the rotation version."
  }
}

# CUSTOM mode advertises only what is listed. advertised_groups = ALL_SUBNETS
# keeps every subnet of the VPC (what DEFAULT mode announces) next to the
# custom ranges.
run "custom_mode_keeps_all_subnets_group" {
  command = plan

  variables {
    advertised_groups    = ["ALL_SUBNETS"]
    advertised_ip_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition = (
      google_compute_router.router.bgp[0].advertise_mode == "CUSTOM" &&
      tolist(google_compute_router.router.bgp[0].advertised_groups) == tolist(["ALL_SUBNETS"]) &&
      [for r in google_compute_router.router.bgp[0].advertised_ip_ranges : r.range] == ["10.10.0.0/16"]
    )
    error_message = "advertised_groups must reach the router next to the custom ranges."
  }
}

run "explicit_ranges_without_groups_unchanged" {
  command = plan

  variables {
    advertised_ip_ranges = [{ range = "10.0.0.0/12", description = "GCP block" }]
  }

  assert {
    condition     = google_compute_router.router.bgp[0].advertise_mode == "CUSTOM" && length(coalesce(google_compute_router.router.bgp[0].advertised_groups, [])) == 0
    error_message = "Without advertised_groups a CUSTOM router announces only its listed ranges (unchanged)."
  }
}

run "default_mode_without_ranges" {
  command = plan

  assert {
    condition     = google_compute_router.router.bgp[0].advertise_mode == "DEFAULT" && length(coalesce(google_compute_router.router.bgp[0].advertised_groups, [])) == 0
    error_message = "Without custom ranges the router stays in DEFAULT mode."
  }
}

run "rejects_unknown_advertised_group" {
  command = plan

  variables {
    advertised_groups    = ["ALL_PEERS"]
    advertised_ip_ranges = [{ range = "10.10.0.0/16" }]
  }

  expect_failures = [var.advertised_groups]
}
