# Plan assertions for the private-service-connect module: verify the PSC address and
# forwarding rule attach to the caller-supplied network.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "pscendpoint"
  network    = "projects/mock-project/global/networks/mock-vpc"
  address    = "10.0.255.254"
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

run "psc_name_and_address_are_explicit" {
  command = plan

  assert {
    condition     = google_compute_global_forwarding_rule.psc_forwarding_rule.name == "pscendpoint"
    error_message = "The forwarding rule must carry the caller-supplied, Google-compliant name."
  }

  assert {
    condition     = google_compute_global_address.psc_address.address == "10.0.255.254"
    error_message = "The global address must reserve the caller-supplied IPv4 address (Google needs an explicit IP)."
  }

  assert {
    condition     = google_compute_global_address.psc_address.name == "pscendpoint-ip"
    error_message = "The address name must derive from the endpoint name."
  }
}
