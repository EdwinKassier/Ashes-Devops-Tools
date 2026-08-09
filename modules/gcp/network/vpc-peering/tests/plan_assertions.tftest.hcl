# Resource-assertion tests for the network/vpc-peering module.
# The module's defining behavior is that reverse_peering INVERTS the custom-route
# export/import direction relative to the forward peering. Prior tests only
# validated inputs, so a swapped import/export would pass silently
# (audit round-3 §D8 / finding #10). These assert the inversion on the plan.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  peering_name = "test-peering"
  network      = "projects/mock-project/global/networks/mock-vpc"
  peer_network = "projects/peer-project/global/networks/peer-vpc"
}

run "reverse_peering_inverts_custom_route_direction" {
  command = plan

  variables {
    create_reverse_peering = true
    export_custom_routes   = true
    import_custom_routes   = false
  }

  # Forward peering uses the inputs as provided.
  assert {
    condition = (
      google_compute_network_peering.peering.export_custom_routes == true &&
      google_compute_network_peering.peering.import_custom_routes == false
    )
    error_message = "Forward peering must use export/import_custom_routes exactly as provided."
  }

  # Reverse peering must INVERT: its export = forward's import, its import = forward's export.
  assert {
    condition     = google_compute_network_peering.reverse_peering[0].export_custom_routes == false
    error_message = "reverse_peering.export_custom_routes must equal var.import_custom_routes (inverted)."
  }
  assert {
    condition     = google_compute_network_peering.reverse_peering[0].import_custom_routes == true
    error_message = "reverse_peering.import_custom_routes must equal var.export_custom_routes (inverted)."
  }
}

run "no_reverse_peering_when_disabled" {
  command = plan

  variables {
    create_reverse_peering = false
  }

  assert {
    condition     = length(google_compute_network_peering.reverse_peering) == 0
    error_message = "reverse_peering must not be created when create_reverse_peering = false."
  }
}
