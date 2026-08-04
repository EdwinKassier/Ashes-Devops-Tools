# Variable-validation tests for the aws-backup stage.
#
# Uses two mock providers so no AWS credentials are required. The accept case
# reaches (and passes) plan with the module defaults plus the three required
# ARNs/OU id; the reject case fails the changeable_for_days validation (WORM
# cooling-off minimum) before any resource is evaluated.

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  restore_testing_role_arn = "arn:aws:iam::444444444444:role/backup-restore-test"
  backup_role_arn          = "arn:aws:iam::111111111111:role/aws-backup-role"
  workloads_ou_id          = "ou-abcd-11111111"
}

run "defaults_accepted" {
  # Accept case: the defaults (org-backup-vault, 7/3650/3, eu-west-2) plus the
  # required ARNs/OU id must pass all validations and plan.
  command = plan
}

run "invalid_changeable_for_days_rejected" {
  # Reject case: a sub-3 cooling-off window must fail the Compliance-mode
  # Vault Lock validation.
  command = plan

  variables {
    changeable_for_days = 2
  }

  expect_failures = [var.changeable_for_days]
}
