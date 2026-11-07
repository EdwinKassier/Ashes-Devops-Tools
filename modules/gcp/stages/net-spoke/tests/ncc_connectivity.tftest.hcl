# Plan assertions for stages/net-spoke hub connectivity: VPC peering (default)
# versus an opt-in Network Connectivity Center spoke (mock providers).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
  mock_resource "google_service_networking_connection" {
    override_during = plan
    defaults = {
      peering = "servicenetworking-googleapis-com"
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id     = "mock-host-project"
  project_prefix = "mock-dev"
  region         = "europe-west1"
  network = {
    name           = "mock-dev-vpc"
    cidr_block     = "10.10.0.0/16"
    explicit_zones = ["europe-west1-b", "europe-west1-c"]
  }
  peerings = {
    "hub-peering" = {
      peer_network         = "projects/hub/global/networks/hub-vpc-core"
      export_custom_routes = true
      import_custom_routes = true
    }
  }
}

run "peering_mode_keys_unchanged" {
  command = plan

  # connectivity defaults to peering: the existing peering keys (and so the
  # module.vpc_peering["<key>"] state addresses) are unchanged; no NCC spoke.
  assert {
    condition     = keys(module.vpc_peering) == ["hub-peering"] && module.vpc_peering["hub-peering"].peering.name == "hub-peering"
    error_message = "In peering mode module.vpc_peering must keep one instance per peerings key, unchanged."
  }

  assert {
    condition     = length(module.ncc_spoke) == 0 && output.ncc_spoke_id == null && output.ncc_producer_spoke_ids == {}
    error_message = "Peering mode must not plan an NCC spoke."
  }
}

run "ncc_mode_no_peering_instances" {
  command = plan

  variables {
    connectivity = "ncc"
    ncc = {
      hub_id = "projects/mock-hub-project/locations/global/hubs/mock-hub"
    }
  }

  assert {
    condition     = length(module.vpc_peering) == 0 && output.peering_states == {}
    error_message = "NCC mode must plan no VPC peering instance (NCC rejects a spoke VPC that is still peered)."
  }

  assert {
    condition     = length(module.ncc_spoke) == 1 && module.ncc_spoke[0].name == "mock-dev-vpc"
    error_message = "NCC mode must plan one NCC spoke named after the VPC."
  }

  assert {
    condition     = endswith(module.ncc_spoke[0].group, "/hubs/mock-hub/groups/edge")
    error_message = "The spoke VPC must join the STAR hub's edge group by default."
  }
}

run "ncc_mode_psa_producer_spoke" {
  command = plan

  variables {
    connectivity = "ncc"
    ncc = {
      hub_id = "projects/mock-hub-project/locations/global/hubs/mock-hub"
    }
  }

  assert {
    condition     = keys(module.ncc_spoke[0].producer_spoke_ids) == ["psa"]
    error_message = "With PSA enabled (the default), NCC mode must add a PSA producer VPC spoke."
  }
}

run "ncc_mode_psa_producer_spoke_opt_out" {
  command = plan

  variables {
    connectivity = "ncc"
    ncc = {
      hub_id                        = "projects/mock-hub-project/locations/global/hubs/mock-hub"
      group                         = "default"
      export_private_service_access = false
    }
  }

  assert {
    condition     = module.ncc_spoke[0].producer_spoke_ids == {} && endswith(module.ncc_spoke[0].group, "/groups/default")
    error_message = "export_private_service_access = false must drop the producer spoke; group must pass through (MESH: default)."
  }
}
