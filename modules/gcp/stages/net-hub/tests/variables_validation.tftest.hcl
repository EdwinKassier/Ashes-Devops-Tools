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
  expect_failures = [var.vpn_shared_secret_wo]
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

run "rejects_unknown_ncc_topology" {
  command = plan

  variables {
    ncc = {
      enabled         = true
      preset_topology = "RING"
    }
  }

  expect_failures = [var.ncc]
}

run "rejects_vpn_with_both_secret_forms" {
  command = plan
  variables {
    vpn                  = { enabled = true, peer_gateway_ips = ["203.0.113.1", "203.0.113.2"] }
    vpn_shared_secret    = "mock-legacy"
    vpn_shared_secret_wo = "mock-wo"
  }
  expect_failures = [var.vpn_shared_secret_wo]
}

run "rejects_published_proxy_without_consumers" {
  command = plan

  variables {
    secure_web_proxy = {
      enabled             = true
      psc_nat_subnet_cidr = "10.0.253.0/24"
    }
  }

  expect_failures = [var.secure_web_proxy]
}

run "rejects_malformed_notification_channel" {
  command = plan

  variables {
    alerting = { notification_channel_ids = ["123"] }
  }

  expect_failures = [var.alerting]
}
