# Input validation for stages/net-hub (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id     = "mock-hub-project"
  project_prefix = "mock"
  network = {
    name       = "hub-vpc-core"
    cidr_block = "10.0.0.0/16"
  }
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_invalid_project_id" {
  command = plan
  variables {
    project_id = "x"
  }
  expect_failures = [var.project_id]
}

run "rejects_invalid_cidr" {
  command = plan
  variables {
    network = { name = "hub-vpc-core", cidr_block = "10.0.0.0" }
  }
  expect_failures = [var.network]
}

run "rejects_vpn_without_shared_secret" {
  command = plan
  variables {
    vpn = { enabled = true, peer_gateway_ips = ["203.0.113.1", "203.0.113.2"] }
  }
  expect_failures = [var.vpn_shared_secret]
}

run "rejects_invalid_vpn_tunnel_count" {
  command = plan
  variables {
    vpn = { tunnel_count = 3 }
  }
  expect_failures = [var.vpn]
}

run "rejects_invalid_nat_allocation" {
  command = plan
  variables {
    nat = { ip_allocate_option = "STATIC" }
  }
  expect_failures = [var.nat]
}

run "rejects_invalid_firewall_mode" {
  command = plan

  variables {
    firewall_mode = "tags"
  }

  expect_failures = [var.firewall_mode]
}
