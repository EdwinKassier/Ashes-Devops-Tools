# Variable validation tests for the aws/kms-key module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

variables {
  alias                 = "central-logs"
  org_id                = "o-abc123xyz0"
  management_account_id = "111122223333"
  key_admin_arn         = "arn:aws:iam::111122223333:role/KeyAdmin"
}

run "defaults_accepted" {
  # Accept case: defaults (30-day window, default log-service principals) pass.
  command = plan
}

run "short_deletion_window_rejected" {
  # Reject case: a 3-day window is below the AWS minimum of 7.
  command = plan

  variables {
    deletion_window_in_days = 3
  }

  expect_failures = [var.deletion_window_in_days]
}
