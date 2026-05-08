# Variable validation tests for the vpn module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id                = "mock-project"
  name                      = "test-vpn"
  network                   = "projects/mock-project/global/networks/mock-vpc"
  region                    = "europe-west1"
  peer_external_gateway_ips = ["203.0.113.1", "203.0.113.2"]
  shared_secret             = "mock-secret"
}

# ── tunnel_count ───────────────────────────────────────────────────────────────

run "accepts_tunnel_count_one" {
  command = plan

  variables {
    tunnel_count              = 1
    peer_external_gateway_ips = ["203.0.113.1"]
  }
}

run "accepts_tunnel_count_two" {
  command = plan

  variables {
    tunnel_count              = 2
    peer_external_gateway_ips = ["203.0.113.1", "203.0.113.2"]
  }
}

run "rejects_tunnel_count_zero" {
  command = plan

  expect_failures = [var.tunnel_count]

  variables {
    tunnel_count = 0
  }
}

run "rejects_tunnel_count_three" {
  command = plan

  expect_failures = [var.tunnel_count]

  variables {
    tunnel_count = 3
  }
}

# ── peer_external_gateway_ips ─────────────────────────────────────────────────

run "accepts_single_ip_for_single_tunnel" {
  command = plan

  variables {
    tunnel_count              = 1
    peer_external_gateway_ips = ["203.0.113.1"]
  }
}

run "accepts_two_distinct_ips_for_ha" {
  command = plan

  variables {
    tunnel_count              = 2
    peer_external_gateway_ips = ["203.0.113.1", "203.0.113.2"]
  }
}

run "rejects_too_few_ips_for_tunnel_count" {
  command = plan

  expect_failures = [var.peer_external_gateway_ips]

  variables {
    tunnel_count              = 2
    peer_external_gateway_ips = ["203.0.113.1"]
  }
}

run "rejects_invalid_ip_format" {
  command = plan

  expect_failures = [var.peer_external_gateway_ips]

  variables {
    peer_external_gateway_ips = ["not-an-ip", "203.0.113.2"]
  }
}

# ── peer_ip_addresses / local_ip_addresses guard ──────────────────────────────

run "rejects_peer_ips_fewer_than_tunnel_count" {
  command = plan

  expect_failures = [var.peer_ip_addresses]

  variables {
    tunnel_count      = 2
    peer_ip_addresses = ["169.254.0.2"]
  }
}

run "rejects_local_ips_fewer_than_tunnel_count" {
  command = plan

  expect_failures = [var.local_ip_addresses]

  variables {
    tunnel_count       = 2
    local_ip_addresses = ["169.254.0.1"]
  }
}
