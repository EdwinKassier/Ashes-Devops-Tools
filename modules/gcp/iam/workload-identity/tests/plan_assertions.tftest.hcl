# Plan assertions for the iam/workload-identity module: verify the WIF pool is planned
# with the caller-supplied id and display name.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  pool_id      = "test-pool"
  display_name = "Test Pool"
}

run "pool_wired" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool.pool.workload_identity_pool_id == var.pool_id
    error_message = "WIF pool id must be the caller-supplied pool_id."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.display_name == var.display_name
    error_message = "WIF pool display name must be the caller-supplied display_name."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.project == var.project_id
    error_message = "WIF pool must be created in the caller-supplied project."
  }
}
