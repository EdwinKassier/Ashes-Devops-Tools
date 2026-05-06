# Variable validation tests for the iam/workload_identity module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  pool_id      = "test-pool"
  display_name = "Test Pool"
}

# ── pool_id ────────────────────────────────────────────────────────────────────

run "accepts_valid_pool_id" {
  command = plan

  variables {
    pool_id = "github-pool"
  }
}

run "accepts_pool_id_with_numbers" {
  command = plan

  variables {
    pool_id = "gh-pool-01"
  }
}

run "rejects_pool_id_starting_with_number" {
  command = plan

  expect_failures = [var.pool_id]

  variables {
    pool_id = "1invalid-pool"
  }
}

run "rejects_pool_id_with_uppercase" {
  command = plan

  expect_failures = [var.pool_id]

  variables {
    pool_id = "GitHub-Pool"
  }
}

run "rejects_pool_id_too_short" {
  command = plan

  expect_failures = [var.pool_id]

  variables {
    pool_id = "ab"
  }
}

run "rejects_pool_id_ending_with_hyphen" {
  command = plan

  expect_failures = [var.pool_id]

  variables {
    pool_id = "github-pool-"
  }
}
