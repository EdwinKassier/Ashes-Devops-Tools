# The opt-in NCC hub in the network-hub stage: off by default, and its hub ID
# and spoke group reach the stage outputs (gcp-network-hub contract). The NCC
# resources themselves are asserted in stages/net-hub and network/ncc-*.

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
    shared = { id = "folders/111111111", name = "folders/111111111", display_name = "Shared" }
  }
}

override_data {
  target = module.dns_anchor.data.google_compute_zones.available
  values = {
    names = ["us-central1-a"]
  }
}

override_module {
  target = module.dns_anchor.module.network
  outputs = {
    network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_id        = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_name      = "dns-vpc-core"
    subnets           = { public = {}, private = {}, database = {} }
  }
}

run "ncc_hub_off_by_default" {
  command = plan

  override_module {
    target = module.hub
    outputs = {
      network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
      network_name      = "hub-vpc-core"
      subnets           = { public = {}, private = {}, database = {} }
      ncc_hub_id        = null
      ncc_spoke_group   = null
    }
  }

  assert {
    condition     = var.enable_ncc_hub == false && output.ncc_hub_id == null && output.ncc_spoke_group == null
    error_message = "The NCC hub must be opt-in, with null hub outputs when off."
  }
}

run "ncc_hub_outputs_pass_through" {
  command = plan

  variables {
    enable_ncc_hub = true
  }

  override_module {
    target = module.hub
    outputs = {
      network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
      network_name      = "hub-vpc-core"
      subnets           = { public = {}, private = {}, database = {} }
      ncc_hub_id        = "projects/mock-hub-project/locations/global/hubs/mock-ncc-hub"
      ncc_spoke_group   = "edge"
    }
  }

  assert {
    condition     = output.ncc_hub_id == "projects/mock-hub-project/locations/global/hubs/mock-ncc-hub" && output.ncc_spoke_group == "edge"
    error_message = "ncc_hub_id / ncc_spoke_group must come from module.hub."
  }
}
