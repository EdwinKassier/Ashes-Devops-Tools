# Regression test: when create_router is true and router_name is unset (default ""),
# the router name must be auto-generated as "<nat name>-router".
# The base variables block intentionally omits router_name so the empty-name path
# is actually exercised (the validation test's base pins router_name and masks this bug).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "test-nat"
  region     = "europe-west1"
  network    = "projects/mock-project/global/networks/mock-vpc"
  # router_name intentionally omitted → defaults to "" → auto-generation path.
}

run "auto_generates_router_name_when_unset" {
  command = plan

  assert {
    condition     = google_compute_router.router[0].name == "${var.name}-router"
    error_message = "router name must default to <nat name>-router when router_name is empty"
  }
}
