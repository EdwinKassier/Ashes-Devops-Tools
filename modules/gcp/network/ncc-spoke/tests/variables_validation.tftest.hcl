# Variable validation tests for network/ncc-spoke (mock provider).

mock_provider "google" {}

variables {
  project_id = "mock-spoke-project"
  name       = "mock-dev-vpc"
  hub_id     = "projects/mock-hub-project/locations/global/hubs/mock-hub"
  linked_vpc_network = {
    uri = "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/global/networks/mock-dev-vpc"
  }
}

run "accepts_vpc_spoke" {
  command = plan
}

run "rejects_no_link" {
  command = plan

  variables {
    linked_vpc_network = null
    location           = "europe-west1"
  }

  expect_failures = [var.linked_vpc_network]
}

run "rejects_both_links" {
  command = plan

  variables {
    linked_vpn_tunnels = {
      uris = ["https://www.googleapis.com/compute/v1/projects/mock-spoke-project/regions/europe-west1/vpnTunnels/t0"]
    }
  }

  expect_failures = [var.linked_vpc_network]
}

run "rejects_regional_vpc_spoke" {
  command = plan

  variables {
    location = "europe-west1"
  }

  expect_failures = [var.location]
}

run "rejects_unknown_group" {
  command = plan

  variables {
    group = "spokes"
  }

  expect_failures = [var.group]
}

run "rejects_malformed_hub_id" {
  command = plan

  variables {
    hub_id = "mock-hub"
  }

  expect_failures = [var.hub_id]
}

run "rejects_producer_without_vpc" {
  command = plan

  variables {
    linked_vpc_network = null
    location           = "europe-west1"
    linked_vpn_tunnels = {
      uris = ["https://www.googleapis.com/compute/v1/projects/mock-spoke-project/regions/europe-west1/vpnTunnels/t0"]
    }
    producer_vpc_networks = {
      psa = { network = "mock-dev-vpc", peering = "servicenetworking-googleapis-com" }
    }
  }

  expect_failures = [var.producer_vpc_networks]
}

run "rejects_empty_vpn_tunnel_list" {
  command = plan

  variables {
    linked_vpc_network = null
    location           = "europe-west1"
    linked_vpn_tunnels = { uris = [] }
  }

  expect_failures = [var.linked_vpn_tunnels]
}
