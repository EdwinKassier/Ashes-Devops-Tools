# Variable validation tests for the compute_dashboard module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
}

# ── latency_threshold_ms ───────────────────────────────────────────────────────

run "accepts_valid_latency_threshold" {
  command = plan

  variables {
    latency_threshold_ms = 500
  }
}

run "rejects_zero_latency_threshold" {
  command = plan

  expect_failures = [var.latency_threshold_ms]

  variables {
    latency_threshold_ms = 0
  }
}

run "rejects_negative_latency_threshold" {
  command = plan

  expect_failures = [var.latency_threshold_ms]

  variables {
    latency_threshold_ms = -1
  }
}

# ── error_rate_threshold_percent ───────────────────────────────────────────────

run "accepts_error_rate_at_zero" {
  command = plan

  variables {
    error_rate_threshold_percent = 0.0
  }
}

run "accepts_error_rate_at_100" {
  command = plan

  variables {
    error_rate_threshold_percent = 100.0
  }
}

run "rejects_negative_error_rate" {
  command = plan

  expect_failures = [var.error_rate_threshold_percent]

  variables {
    error_rate_threshold_percent = -0.1
  }
}

run "rejects_error_rate_above_100" {
  command = plan

  expect_failures = [var.error_rate_threshold_percent]

  variables {
    error_rate_threshold_percent = 100.1
  }
}
