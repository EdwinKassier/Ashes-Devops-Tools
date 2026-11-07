# Plan assertions for the opt-in NCC hub in stages/net-hub (mock providers).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b"]
    }
  }
  mock_resource "google_network_connectivity_hub" {
    override_during = plan
    defaults = {
      id = "projects/mock-hub-project/locations/global/hubs/mock-ncc-hub"
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
  project_id     = "mock-hub-project"
  project_prefix = "mock"
  region         = "us-central1"
  network = {
    name       = "hub-vpc-core"
    cidr_block = "10.0.0.0/16"
  }
}

run "ncc_off_by_default" {
  command = plan

  assert {
    condition     = length(module.ncc_hub) == 0 && length(module.ncc_hub_spoke) == 0 && output.ncc_hub_id == null && output.ncc_spoke_group == null
    error_message = "The NCC hub must be opt-in."
  }
}

run "ncc_star_hub_with_center_spoke" {
  command = plan

  variables {
    ncc = { enabled = true }
  }

  assert {
    condition     = module.ncc_hub[0].name == "mock-ncc-hub" && module.ncc_hub[0].preset_topology == "STAR"
    error_message = "The hub must default to <project_prefix>-ncc-hub with the STAR topology."
  }

  assert {
    condition     = output.ncc_hub_id == "projects/mock-hub-project/locations/global/hubs/mock-ncc-hub" && output.ncc_spoke_group == "edge"
    error_message = "net-hub must publish the hub ID and the edge group for environment spokes."
  }

  assert {
    condition     = module.ncc_hub_spoke[0].group == "projects/mock-hub-project/locations/global/hubs/mock-ncc-hub/groups/center"
    error_message = "The hub VPC must join the STAR hub's center group."
  }

  assert {
    condition     = keys(module.ncc_hub_spoke[0].producer_spoke_ids) == ["psa"]
    error_message = "With PSA enabled, the hub PSA peering must get a producer VPC spoke."
  }

  assert {
    condition     = length(module.ncc_hub[0].auto_accept_projects) == 0
    error_message = "No auto-accept list unless ncc.auto_accept_projects is set."
  }
}

run "ncc_auto_accept_projects_pass_through" {
  command = plan

  variables {
    ncc = {
      enabled              = true
      auto_accept_projects = ["333333333333"]
    }
  }

  assert {
    condition     = module.ncc_hub[0].auto_accept_projects == tolist(["333333333333"])
    error_message = "ncc.auto_accept_projects must reach network/ncc-hub."
  }
}

run "ncc_mesh_hub_uses_default_group" {
  command = plan

  variables {
    ncc = {
      enabled         = true
      name            = "custom-hub"
      preset_topology = "MESH"
    }
  }

  assert {
    condition     = module.ncc_hub[0].name == "custom-hub" && output.ncc_spoke_group == "default" && endswith(module.ncc_hub_spoke[0].group, "/groups/default")
    error_message = "A MESH hub puts every spoke in the default group."
  }
}
