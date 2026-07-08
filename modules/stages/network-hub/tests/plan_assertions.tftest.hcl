# Regression test for the DNS-hub network wiring.
#
# module.dns_hub_zone.private_visibility_networks is fed
# module.dns_hub_network.network_self_link (see main.tf) so the private DNS
# zone resolves against the DNS hub's own VPC. This asserts that wiring
# actually reaches the planned google_dns_managed_zone resource — the existing
# variables_validation.tftest.hcl overrides module.dns_hub_zone away entirely
# and never proves this connection.
#
# module.hub_network / module.dns_hub_network are still overridden (they wrap
# modules/host, which has a data.google_compute_zones postcondition that fails
# under mock_provider) but module.dns_hub_zone is left real so its resource
# plans.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix         = "mock"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  default_region         = "us-central1"
  hub_project_id         = "mock-hub-project"
  dns_project_id         = "mock-dns-project"
  spoke_project_numbers  = {}
  org_id                 = "organizations/123456789"
  internal_domain        = "internal.example.com"
  folders = {
    shared = {
      id           = "folders/111111111"
      name         = "folders/111111111"
      display_name = "Shared"
    }
  }
}

run "dns_zone_binds_to_dns_hub_network_self_link" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }

  assert {
    condition     = length(module.dns_hub_zone.zone.private_visibility_config) > 0
    error_message = "the private DNS zone must actually be planned with a private_visibility_config block"
  }

  assert {
    condition = length(module.dns_hub_zone.zone.private_visibility_config[0].networks) > 0 && alltrue([
      for n in module.dns_hub_zone.zone.private_visibility_config[0].networks :
      n.network_url == "projects/mock-dns-project/global/networks/dns-vpc-core"
    ])
    error_message = "the private DNS zone must bind to the DNS hub's own VPC self_link (module.dns_hub_network.network_self_link), not the shared-vpc hub network"
  }
}
