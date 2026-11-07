# Plan assertions for network/ncc-spoke (mock provider, no credentials).

mock_provider "google" {}

variables {
  project_id = "mock-spoke-project"
  name       = "mock-dev-vpc"
  hub_id     = "projects/mock-hub-project/locations/global/hubs/mock-hub"
}

run "ncc_spoke_edge_group_links_vpc" {
  command = plan

  variables {
    linked_vpc_network = {
      uri                   = "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/global/networks/mock-dev-vpc"
      exclude_export_ranges = ["10.10.255.0/24"]
    }
  }

  assert {
    condition     = google_network_connectivity_spoke.this.group == "projects/mock-hub-project/locations/global/hubs/mock-hub/groups/edge"
    error_message = "A spoke VPC must join the hub's edge group (<hub id>/groups/edge) by default."
  }

  assert {
    condition     = google_network_connectivity_spoke.this.hub == var.hub_id && google_network_connectivity_spoke.this.location == "global"
    error_message = "A VPC spoke must attach to the given hub at location global."
  }

  assert {
    condition     = google_network_connectivity_spoke.this.linked_vpc_network[0].uri == "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/global/networks/mock-dev-vpc"
    error_message = "The spoke must link the given VPC network."
  }

  assert {
    condition     = google_network_connectivity_spoke.this.linked_vpc_network[0].exclude_export_ranges == tolist(["10.10.255.0/24"]) && google_network_connectivity_spoke.this.linked_vpc_network[0].include_export_ranges == null
    error_message = "Export range filters must pass through; empty ones go to the API as null."
  }

  assert {
    condition     = length(google_network_connectivity_spoke.this.linked_vpn_tunnels) == 0 && length(google_network_connectivity_spoke.producer) == 0
    error_message = "No VPN link and no producer spoke unless configured."
  }
}

run "psa_producer_spoke_same_group_after_consumer" {
  command = plan

  variables {
    linked_vpc_network = {
      uri = "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/global/networks/mock-dev-vpc"
    }
    producer_vpc_networks = {
      psa = {
        network = "mock-dev-vpc"
        peering = "servicenetworking-googleapis-com"
      }
    }
  }

  # The name is kept from the task brief. "after consumer" is NOT asserted here:
  # terraform test cannot assert apply order. The ordering comes from the
  # producer spoke reading hub and group from the consumer spoke (a reference
  # dependency) plus an explicit depends_on in main.tf. This run asserts only
  # what a plan can show: the same hub and group.
  assert {
    condition     = google_network_connectivity_spoke.producer["psa"].group == google_network_connectivity_spoke.this.group && google_network_connectivity_spoke.producer["psa"].hub == google_network_connectivity_spoke.this.hub
    error_message = "The PSA producer spoke must join the same hub group as its consumer VPC spoke."
  }

  assert {
    condition     = google_network_connectivity_spoke.producer["psa"].name == "mock-dev-vpc-psa" && google_network_connectivity_spoke.producer["psa"].location == "global"
    error_message = "The producer spoke must be named <name>-<key> at location global."
  }

  assert {
    condition = (
      google_network_connectivity_spoke.producer["psa"].linked_producer_vpc_network[0].network == "mock-dev-vpc" &&
      google_network_connectivity_spoke.producer["psa"].linked_producer_vpc_network[0].peering == "servicenetworking-googleapis-com"
    )
    error_message = "The producer spoke must link the consumer network through the service networking peering."
  }
}

run "vpn_spoke_is_regional" {
  command = plan

  variables {
    location = "europe-west1"
    group    = "center"
    linked_vpn_tunnels = {
      uris = [
        "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/regions/europe-west1/vpnTunnels/t0",
        "https://www.googleapis.com/compute/v1/projects/mock-spoke-project/regions/europe-west1/vpnTunnels/t1",
      ]
    }
  }

  assert {
    condition     = google_network_connectivity_spoke.this.location == "europe-west1" && length(google_network_connectivity_spoke.this.linked_vpn_tunnels[0].uris) == 2
    error_message = "A VPN spoke must be regional and link every tunnel."
  }

  assert {
    condition     = google_network_connectivity_spoke.this.linked_vpn_tunnels[0].site_to_site_data_transfer == false && length(google_network_connectivity_spoke.this.linked_vpc_network) == 0
    error_message = "Site-to-site data transfer must be opt-in and no VPC link planned."
  }
}
