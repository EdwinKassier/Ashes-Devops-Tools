# Plan assertions for the subnet module: verify the google_compute_subnetwork is
# planned with the caller-supplied identity/CIDR/network wired through.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id    = "mock-project"
  subnet_name   = "mock-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "europe-west1"
  network       = "projects/mock-project/global/networks/mock-vpc"
}

run "subnetwork_wired" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet.name == var.subnet_name
    error_message = "Subnetwork name must be the caller-supplied subnet_name."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.ip_cidr_range == var.ip_cidr_range
    error_message = "Subnetwork primary CIDR must be the caller-supplied ip_cidr_range."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.network == var.network
    error_message = "Subnetwork must attach to the caller-supplied network."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.project == var.project_id
    error_message = "Subnetwork must be created in the caller-supplied project."
  }
}
