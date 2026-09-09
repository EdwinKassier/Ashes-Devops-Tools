# Plan assertions for the private-service-connect module: verify the PSC address and
# forwarding rule attach to the caller-supplied network.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "psc-endpoint"
  network    = "projects/mock-project/global/networks/mock-vpc"
}

run "psc_wired_to_network" {
  command = plan

  assert {
    condition     = google_compute_global_address.psc_address.network == var.network
    error_message = "PSC address must be reserved on the caller-supplied network."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.psc_forwarding_rule.network == var.network
    error_message = "PSC forwarding rule must target the caller-supplied network."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.psc_forwarding_rule.name == var.name
    error_message = "PSC forwarding rule name must be the caller-supplied name."
  }
}
