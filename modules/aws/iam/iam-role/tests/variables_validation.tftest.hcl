# Variable validation tests for the aws/iam-role module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: module defaults (empty roles, break-glass enabled) must pass.
  command = plan
}

run "bad_trusted_principal_rejected" {
  # Reject case: a principal that is not an account-qualified IAM ARN must fail.
  command = plan

  variables {
    break_glass_trusted_principals = ["not-an-arn"]
  }

  expect_failures = [var.break_glass_trusted_principals]
}
