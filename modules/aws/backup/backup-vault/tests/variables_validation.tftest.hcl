# Variable validation tests for the aws/backup-vault module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: defaults plus the required role ARN must pass all validations.
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
  }
}

run "changeable_for_days_below_minimum_rejected" {
  # Reject case: changeable_for_days = 1 is below the Compliance-mode minimum.
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
    changeable_for_days      = 1
  }

  expect_failures = [var.changeable_for_days]
}
