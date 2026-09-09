# Plan assertions for the vpc module: verify the google_compute_network is planned
# with the caller-supplied identity/config wired through (not hardcoded).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  vpc_name   = "mock-vpc"
}

run "network_identity_and_config_wired" {
  command = plan

  assert {
    condition     = google_compute_network.vpc.name == var.vpc_name
    error_message = "Network name must be the caller-supplied vpc_name."
  }

  assert {
    condition     = google_compute_network.vpc.project == var.project_id
    error_message = "Network must be created in the caller-supplied project."
  }

  assert {
    condition     = google_compute_network.vpc.auto_create_subnetworks == var.auto_create_subnetworks
    error_message = "auto_create_subnetworks must reflect the input variable."
  }

  assert {
    condition     = google_compute_network.vpc.routing_mode == var.routing_mode
    error_message = "routing_mode must reflect the input variable."
  }
}
