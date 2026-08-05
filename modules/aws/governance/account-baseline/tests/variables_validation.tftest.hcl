# Variable validation tests for the aws/account-baseline module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: module defaults must pass all validations.
  command = plan
}

run "weak_password_length_rejected" {
  # Reject case: a sub-14 minimum password length must trip the CIS validation.
  command = plan

  variables {
    password_min_length = 8
  }

  expect_failures = [var.password_min_length]
}
