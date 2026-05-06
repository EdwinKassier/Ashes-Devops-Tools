# Variable validation tests for the vpn module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id             = "mock-project"
  name                   = "test-vpn"
  network                = "projects/mock-project/global/networks/mock-vpc"
  region                 = "europe-west1"
  peer_external_gateway_ip = "203.0.113.1"
  shared_secret          = "mock-secret"
}

# ── tunnel_count ───────────────────────────────────────────────────────────────

run "accepts_tunnel_count_one" {
  command = plan

  variables {
    tunnel_count = 1
  }
}

run "accepts_tunnel_count_two" {
  command = plan

  variables {
    tunnel_count = 2
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
