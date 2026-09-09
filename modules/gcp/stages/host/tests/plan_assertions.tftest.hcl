# Plan assertions for the host stage: verify the composed VPC identity is wired through
# to the stage outputs when networking is enabled.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id        = "mock-project"
  project_prefix    = "mock"
  vpc_cidr_block    = "10.0.0.0/16"
  vpc_name          = "mock-vpc"
  enable_networking = true
}

run "network_outputs_wired_from_vpc_module" {
  command = plan

  assert {
    condition     = output.network_name == var.vpc_name
    error_message = "Stage network_name output must come from the composed VPC module."
  }

  assert {
    condition     = length(output.network_tags) >= 1
    error_message = "Stage must expose the tiered network tags."
  }
}

run "networking_disabled_falls_back_to_existing_network" {
  command = plan

  variables {
    enable_networking     = false
    existing_network_name = "shared-host-vpc"
  }

  assert {
    condition     = output.network_name == "shared-host-vpc"
    error_message = "With networking disabled, network_name must fall back to existing_network_name."
  }
}
