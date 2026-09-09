# Plan assertions for the private-service-access module: verify the reserved range
# and the service-networking connection attach to the caller-supplied VPC.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  vpc_network = "projects/mock-project/global/networks/mock-vpc"
}

run "psa_wired_to_network" {
  command = plan

  assert {
    condition     = google_compute_global_address.private_ip_alloc.network == var.vpc_network
    error_message = "Reserved PSA range must be allocated on the caller-supplied VPC network."
  }

  assert {
    condition     = google_compute_global_address.private_ip_alloc.project == var.project_id
    error_message = "Reserved PSA range must be created in the caller-supplied project."
  }

  assert {
    condition     = google_service_networking_connection.private_service_access.network == var.vpc_network
    error_message = "Service networking connection must attach to the caller-supplied VPC network."
  }
}
