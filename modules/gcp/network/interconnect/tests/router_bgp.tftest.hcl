# Regression test: advertised_groups must be unset when advertise_mode is DEFAULT.
# GCP rejects advertised_groups unless advertise_mode = "CUSTOM".
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "us-central1"
  network         = "projects/mock-project/global/networks/mock-vpc"
  attachment_name = "test-attachment"
  router_name     = "test-router"
}

run "default_mode_omits_advertised_groups" {
  command = plan

  # No advertised_ip_ranges → advertise_mode is DEFAULT → advertised_groups must be null/empty.
  assert {
    condition     = try(length(google_compute_router.router[0].bgp[0].advertised_groups), 0) == 0
    error_message = "advertised_groups must be unset when advertise_mode is DEFAULT"
  }
}
