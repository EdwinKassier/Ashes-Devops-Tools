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

run "wildcard_key_user_rejected" {
  # Reject case: a wildcard-account key user would grant usage org-wide.
  command = plan

  variables {
    key_user_arns = ["arn:aws:iam::*:role/LogReader"]
  }

  expect_failures = [var.key_user_arns]
}

run "wildcard_key_policy_admin_rejected" {
  command = plan

  variables {
    key_policy_admin_arns = ["arn:aws:iam::111122223333:role/*"]
  }

  expect_failures = [var.key_policy_admin_arns]
}

run "invalid_service_principal_scope_rejected" {
  command = plan

  variables {
    service_principal_scope = "global"
  }

  expect_failures = [var.service_principal_scope]
}

run "invalid_key_account_id_rejected" {
  command = plan

  variables {
    key_account_id = "12345"
  }

  expect_failures = [var.key_account_id]
}
