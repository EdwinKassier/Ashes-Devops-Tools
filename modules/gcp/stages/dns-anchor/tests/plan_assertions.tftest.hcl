# Plan assertions for stages/dns-anchor (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id = "mock-dns-project"
  region     = "us-central1"
  network = {
    name       = "dns-vpc-core"
    cidr_block = "10.1.0.0/16"
  }
  dns_zones = {
    "internal-root" = {
      dns_name    = "internal.example.com."
      description = "Root Internal Zone for Organization"
    }
  }
}

# The anchor's network core is stubbed so the zone's private-visibility binding
# can be asserted against a known self_link.
override_module {
  target = module.network
  outputs = {
    network_id        = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_name      = "dns-vpc-core"
    subnets           = { public = {}, private = {}, database = {} }
  }
}

run "zones_bind_to_anchor_vpc_with_logging" {
  command = plan

  assert {
    condition     = keys(module.dns_zones) == ["internal-root"] && output.dns_zone_names == { "internal-root" = "internal-root" }
    error_message = "One private zone must be planned per dns_zones entry, named by its key."
  }

  assert {
    condition = length(module.dns_zones["internal-root"].zone.private_visibility_config[0].networks) == 1 && alltrue([
      for n in module.dns_zones["internal-root"].zone.private_visibility_config[0].networks :
      n.network_url == "projects/mock-dns-project/global/networks/dns-vpc-core"
    ])
    error_message = "Every zone must bind to the anchor VPC."
  }

  assert {
    condition     = module.dns_zones["internal-root"].zone.visibility == "private" && module.dns_zones["internal-root"].zone.cloud_logging_config[0].enable_logging
    error_message = "Zones must be private with query logging on."
  }

  assert {
    condition     = output.dns_names == { "internal-root" = "internal.example.com." }
    error_message = "dns_names must expose each zone's DNS suffix."
  }
}

run "additional_visibility_networks_and_records" {
  command = plan

  variables {
    dns_zones = {
      "internal-root" = {
        dns_name                       = "internal.example.com."
        additional_visibility_networks = ["projects/other/global/networks/other-vpc"]
        records                        = [{ name = "api.internal.example.com.", type = "A", rrdatas = ["10.1.16.10"] }]
      }
    }
  }

  assert {
    condition     = length(module.dns_zones["internal-root"].zone.private_visibility_config[0].networks) == 2
    error_message = "additional_visibility_networks must be bound alongside the anchor VPC."
  }

  assert {
    condition     = module.dns_zones["internal-root"].zone.description == "Private DNS zone for internal-root"
    error_message = "A zone without a description must get a key-derived default."
  }
}

run "optional_peerings" {
  command = plan

  variables {
    peerings = {
      "to-hub" = { peer_network = "projects/hub/global/networks/hub-vpc-core" }
    }
  }

  assert {
    condition     = keys(module.vpc_peering) == ["to-hub"]
    error_message = "Optional peerings must be planned per entry."
  }
}
