# Variable validation tests for the network/shared-vpc-service module.
# All runs use mock_provider so no GCP credentials are required.
#
# NOTE: google_compute_shared_vpc_service_project only accepts "ABANDON" or ""
# for deletion_policy — "DELETE" is not a valid GCP API value.

mock_provider "google" {}

variables {
  host_project_id    = "mock-host-project"
  service_project_id = "mock-service-project"
}

# ── deletion_policy ────────────────────────────────────────────────────────────

run "accepts_abandon_deletion_policy" {
  command = plan

  variables {
    deletion_policy = "ABANDON"
  }
}

run "accepts_empty_string_deletion_policy" {
  command = plan

  variables {
    deletion_policy = ""
  }
}

run "rejects_invalid_deletion_policy" {
  command = plan

  expect_failures = [var.deletion_policy]

  variables {
    deletion_policy = "DESTROY"
  }
}

run "rejects_delete_deletion_policy" {
  command = plan

  expect_failures = [var.deletion_policy]

  variables {
    deletion_policy = "DELETE"
  }
}
