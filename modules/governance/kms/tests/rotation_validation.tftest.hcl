mock_provider "google" {}

# Minimum required variables for all runs
variables {
  project_id   = "mock-project"
  keyring_name = "test-keyring"
}

# ── Accept boundary ────────────────────────────────────────────────────────────

run "accepts_minimum_rotation_period" {
  # 86400s == 1 day — the lowest allowed value
  command = plan

  variables {
    keys = {
      test-key = { rotation_period = "86400s" }
    }
  }
}

run "accepts_maximum_rotation_period" {
  # 31536000s == 365 days — the highest allowed value
  command = plan

  variables {
    keys = {
      test-key = { rotation_period = "31536000s" }
    }
  }
}

run "accepts_30_day_rotation" {
  command = plan

  variables {
    keys = {
      data-key    = { rotation_period = "2592000s" }
      signing-key = { rotation_period = "2592000s", purpose = "ASYMMETRIC_SIGN", algorithm = "RSA_SIGN_PKCS1_4096_SHA512" }
    }
  }
}

# ── Reject boundary ────────────────────────────────────────────────────────────

run "rejects_rotation_below_minimum" {
  # 3600s == 1 hour — below the 86400s floor
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      test-key = { rotation_period = "3600s" }
    }
  }
}

run "rejects_rotation_above_maximum" {
  # 31536001s is 1 second beyond the 365-day ceiling
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      test-key = { rotation_period = "31536001s" }
    }
  }
}

run "rejects_zero_rotation" {
  command = plan

  expect_failures = [var.keys]

  variables {
    keys = {
      test-key = { rotation_period = "0s" }
    }
  }
}
