# Variable validation tests for the kms module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  keyring_name = "test-keyring"
}

# ── rotation_period ────────────────────────────────────────────────────────────

run "accepts_minimum_rotation_period_86400s" {
  command = plan

  variables {
    keys = {
      my-key = { rotation_period = "86400s" }
    }
  }
}

run "accepts_maximum_rotation_period_7776000s" {
  command = plan

  variables {
    keys = {
      my-key = { rotation_period = "7776000s" }
    }
  }
}

run "accepts_empty_keys_map" {
  command = plan

  variables {
    keys = {}
  }
}

run "rejects_rotation_period_below_minimum" {
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      short-lived = { rotation_period = "3600s" }
    }
  }
}

run "rejects_rotation_period_above_maximum" {
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      too-long = { rotation_period = "7776001s" }
    }
  }
}

run "rejects_mixed_keys_where_one_violates_policy" {
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      good = { rotation_period = "604800s" }
      bad  = { rotation_period = "3600s" }
    }
  }
}
