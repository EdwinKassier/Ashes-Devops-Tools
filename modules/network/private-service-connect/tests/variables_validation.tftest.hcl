# Variable validation tests for the network/private-service-connect module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "psc-endpoint"
  network    = "projects/mock-project/global/networks/mock-vpc"
}

# ── target ─────────────────────────────────────────────────────────────────────

run "accepts_all_apis_target" {
  command = plan

  variables {
    target = "all-apis"
  }
}

run "accepts_vpc_sc_target" {
  command = plan

  variables {
    target = "vpc-sc"
  }
}

run "accepts_default_target" {
  command = plan
  # Default is "all-apis" — verifies default is valid
}

run "rejects_invalid_target" {
  command = plan

  expect_failures = [var.target]

  variables {
    target = "all-api"
  }
}

run "rejects_service_attachment_uri" {
  command = plan

  expect_failures = [var.target]

  variables {
    target = "projects/my-project/regions/us-central1/serviceAttachments/my-attachment"
  }
}
