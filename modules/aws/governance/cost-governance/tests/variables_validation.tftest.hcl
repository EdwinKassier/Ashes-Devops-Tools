# Variable-validation tests for the aws/cost-governance module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: the module defaults must pass all validations and plan cleanly.
  command = plan
}

run "invalid_threshold_percent_rejected" {
  # Reject case: a threshold_percent above 100 must trip the range validation.
  command = plan

  variables {
    budgets = {
      bad = { limit_amount = "1000", threshold_percent = 150 }
    }
  }

  expect_failures = [var.budgets]
}

run "invalid_anomaly_email_rejected" {
  # Reject case: a malformed anomaly email must trip the email validation.
  command = plan

  variables {
    anomaly_email = "not-an-email"
  }

  expect_failures = [var.anomaly_email]
}
