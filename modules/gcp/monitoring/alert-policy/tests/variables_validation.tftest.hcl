# Variables validation tests for modules/monitoring/alert_policy
#
# Uses mock_provider so no GCP credentials are required.
# Run with: terraform test (from the module root)

mock_provider "google" {}

# ── project_id validation ─────────────────────────────────────────────────────

run "rejects_invalid_project_id_too_short" {
  command = plan

  variables {
    project_id = "ab" # too short (minimum 6 chars: 1 + 4-28 + 1)
  }

  expect_failures = [var.project_id]
}

run "rejects_invalid_project_id_uppercase" {
  command = plan

  variables {
    project_id = "My-Project-123" # uppercase not allowed
  }

  expect_failures = [var.project_id]
}

run "accepts_valid_project_id" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    notification_email_addresses = []
  }
}

# ── notification_email_addresses validation ───────────────────────────────────

run "rejects_invalid_email_no_at_sign" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    notification_email_addresses = ["not-an-email"]
  }

  expect_failures = [var.notification_email_addresses]
}

run "rejects_invalid_email_double_at" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    notification_email_addresses = ["user@@example.com"]
  }

  expect_failures = [var.notification_email_addresses]
}

run "accepts_valid_email_list" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    notification_email_addresses = ["ops@example.com", "on-call@corp.io"]
  }
}

run "accepts_empty_email_list" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    notification_email_addresses = []
  }
}

# ── notification_webhook_urls validation ─────────────────────────────────────

run "rejects_http_webhook_url" {
  command = plan

  variables {
    project_id                = "my-valid-project"
    notification_webhook_urls = { "slack" = "http://hooks.slack.com/services/abc" }
  }

  expect_failures = [var.notification_webhook_urls]
}

run "accepts_https_webhook_url" {
  command = plan

  variables {
    project_id                = "my-valid-project"
    notification_webhook_urls = { "slack" = "https://hooks.slack.com/services/T00/B00/xxx" }
  }
}

# ── cpu_utilization_threshold validation ─────────────────────────────────────

run "rejects_cpu_threshold_zero" {
  command = plan

  variables {
    project_id                = "my-valid-project"
    cpu_utilization_threshold = 0
  }

  expect_failures = [var.cpu_utilization_threshold]
}

run "rejects_cpu_threshold_above_one" {
  command = plan

  variables {
    project_id                = "my-valid-project"
    cpu_utilization_threshold = 1.1
  }

  expect_failures = [var.cpu_utilization_threshold]
}

run "accepts_cpu_threshold_boundary_one" {
  command = plan

  variables {
    project_id                = "my-valid-project"
    cpu_utilization_threshold = 1.0
  }
}

# ── memory_utilization_threshold validation ───────────────────────────────────

run "rejects_memory_threshold_zero" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    memory_utilization_threshold = 0
  }

  expect_failures = [var.memory_utilization_threshold]
}

run "accepts_memory_threshold_point_nine" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    memory_utilization_threshold = 0.9
  }
}

# ── error_rate_threshold_percent validation ───────────────────────────────────

run "rejects_negative_error_rate" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    error_rate_threshold_percent = -0.01
  }

  expect_failures = [var.error_rate_threshold_percent]
}

run "accepts_zero_error_rate" {
  command = plan

  variables {
    project_id                   = "my-valid-project"
    error_rate_threshold_percent = 0
  }
}

# ── latency_p99_threshold_ms validation ──────────────────────────────────────

run "rejects_zero_latency_threshold" {
  command = plan

  variables {
    project_id               = "my-valid-project"
    latency_p99_threshold_ms = 0
  }

  expect_failures = [var.latency_p99_threshold_ms]
}

run "accepts_positive_latency_threshold" {
  command = plan

  variables {
    project_id               = "my-valid-project"
    latency_p99_threshold_ms = 2000
  }
}

# ── alert_alignment_period validation ────────────────────────────────────────

run "rejects_alignment_period_below_60" {
  command = plan

  variables {
    project_id             = "my-valid-project"
    alert_alignment_period = 30
  }

  expect_failures = [var.alert_alignment_period]
}

run "accepts_alignment_period_exactly_60" {
  command = plan

  variables {
    project_id             = "my-valid-project"
    alert_alignment_period = 60
  }
}

# ── alert_duration validation ─────────────────────────────────────────────────

run "rejects_negative_alert_duration" {
  command = plan

  variables {
    project_id     = "my-valid-project"
    alert_duration = -1
  }

  expect_failures = [var.alert_duration]
}

run "accepts_zero_alert_duration_fires_immediately" {
  command = plan

  variables {
    project_id     = "my-valid-project"
    alert_duration = 0
  }
}
