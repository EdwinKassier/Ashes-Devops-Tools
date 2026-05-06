# Variable validation tests for the MODULE_NAME module.
# All runs use mock_provider so no GCP credentials are required.
# Tests use expect_failures — validation blocks fire before resource
# evaluation, so these pass regardless of mock provider behaviour.

mock_provider "google" {}

# Minimum required variables shared across all runs.
variables {
  project_id = "mock-project"
}

# ── variable_name ──────────────────────────────────────────────────────────────

run "accepts_valid_variable_name" {
  command = plan

  variables {
    # variable_name = "valid-value"
  }
}

run "rejects_invalid_variable_name" {
  command = plan

  # expect_failures = [var.variable_name]

  variables {
    # variable_name = "invalid-value"
  }
}
