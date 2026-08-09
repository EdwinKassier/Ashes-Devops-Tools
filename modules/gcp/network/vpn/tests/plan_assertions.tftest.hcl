# Resource-assertion tests for the network/vpn module.
# Prior tests only validated inputs; nothing asserted that tunnel_count actually
# creates N tunnels, that IKEv2 is used, or that shared_secret is wired
# (audit round-3 §D8 / finding #10). These assert the tunnel wiring on the plan.

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
