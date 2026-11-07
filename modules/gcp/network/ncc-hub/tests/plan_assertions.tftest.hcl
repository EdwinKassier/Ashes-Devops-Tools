# Plan assertions for network/ncc-hub (mock provider, no credentials).

mock_provider "google" {
  mock_resource "google_network_connectivity_hub" {
    defaults = {
      id = "projects/mock-hub-project/locations/global/hubs/mock-hub"
    }
  }
}

variables {
  project_id = "mock-hub-project"
  name       = "mock-hub"
}

run "star_hub_preset_policy_by_default" {
  command = apply

  assert {
    condition     = google_network_connectivity_hub.this.policy_mode == "PRESET" && google_network_connectivity_hub.this.preset_topology == "STAR"
    error_message = "The hub must use policy_mode PRESET with the STAR topology by default."
  }

  assert {
    condition     = google_network_connectivity_hub.this.export_psc == false
    error_message = "PSC propagation must be opt-in."
  }

  assert {
    condition = (
      output.group_ids["center"] == "projects/mock-hub-project/locations/global/hubs/mock-hub/groups/center" &&
      output.group_ids["edge"] == "projects/mock-hub-project/locations/global/hubs/mock-hub/groups/edge" &&
      length(output.group_ids) == 2
    )
    error_message = "A STAR hub must expose the service-created center and edge groups as <hub id>/groups/<name>."
  }

  assert {
    condition     = output.spoke_group == "edge" && output.center_group == "center"
    error_message = "STAR spokes join edge; the hub VPC joins center."
  }
}

run "mesh_hub_uses_default_group" {
  command = apply

  variables {
    preset_topology = "MESH"
    export_psc      = true
  }

  assert {
    condition     = google_network_connectivity_hub.this.preset_topology == "MESH" && google_network_connectivity_hub.this.export_psc == true
    error_message = "MESH and export_psc must reach the hub."
  }

  assert {
    condition     = keys(output.group_ids) == ["default"] && output.spoke_group == "default" && output.center_group == "default"
    error_message = "A MESH hub has only the default group."
  }
}
