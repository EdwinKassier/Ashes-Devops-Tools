# Variable validation tests for the billing module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  billing_account      = "012345-6789AB-CDEF01"
  project_id           = "mock-project"
  project_name         = "mock-project"
  monthly_budget_limit = 500
  region               = "europe-west1"
}

# ── monthly_budget_limit ───────────────────────────────────────────────────────

run "accepts_positive_budget_limit" {
  command = plan

  variables {
    monthly_budget_limit = 1000
  }
}

run "rejects_zero_budget_limit" {
  command = plan

  expect_failures = [var.monthly_budget_limit]

  variables {
    monthly_budget_limit = 0
  }
}

run "rejects_negative_budget_limit" {
  command = plan

  expect_failures = [var.monthly_budget_limit]

  variables {
    monthly_budget_limit = -100
  }
}

# ── currency_code ──────────────────────────────────────────────────────────────

run "accepts_three_char_currency_code" {
  command = plan

  variables {
    currency_code = "EUR"
  }
}

run "accepts_usd_currency_code" {
  command = plan

  variables {
    currency_code = "USD"
  }
}

run "rejects_two_char_currency_code" {
  command = plan

  expect_failures = [var.currency_code]

  variables {
    currency_code = "US"
  }
}

run "rejects_four_char_currency_code" {
  command = plan

  expect_failures = [var.currency_code]

  variables {
    currency_code = "EURO"
  }
}

# ── alert_threshold_percent ────────────────────────────────────────────────────

run "accepts_threshold_at_one_hundred_percent" {
  command = plan

  variables {
    alert_threshold_percent = 1.0
  }
}

run "accepts_fifty_percent_threshold" {
  command = plan

  variables {
    alert_threshold_percent = 0.5
  }
}

run "rejects_zero_threshold" {
  command = plan

  expect_failures = [var.alert_threshold_percent]

  variables {
    alert_threshold_percent = 0
  }
}

run "rejects_threshold_above_one" {
  command = plan

  expect_failures = [var.alert_threshold_percent]

  variables {
    alert_threshold_percent = 1.1
  }
}

# ── billing_account ────────────────────────────────────────────────────────────

run "rejects_lowercase_billing_account" {
  command         = plan
  expect_failures = [var.billing_account]
  variables {
    billing_account = "abcdef-123456-789012"
  }
}

run "rejects_billing_account_wrong_segment_count" {
  command         = plan
  expect_failures = [var.billing_account]
  variables {
    billing_account = "ABCDEF-123456"
  }
}

# ── email_recipients ───────────────────────────────────────────────────────────

run "accepts_valid_email_recipients" {
  command = plan
  variables {
    email_recipients = ["alerts@example.com", "ops@company.org"]
  }
}

run "rejects_invalid_email_recipient" {
  command         = plan
  expect_failures = [var.email_recipients]
  variables {
    email_recipients = ["not-an-email"]
  }
}

# ── webhook_service_account ────────────────────────────────────────────────────

run "accepts_empty_webhook_service_account" {
  command = plan
  variables {
    webhook_service_account = ""
  }
}

run "rejects_invalid_webhook_service_account" {
  command         = plan
  expect_failures = [var.webhook_service_account]
  variables {
    webhook_service_account = "not-an-email"
  }
}
