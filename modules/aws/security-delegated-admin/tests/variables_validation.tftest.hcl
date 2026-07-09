# Variable validation tests for the aws/security-delegated-admin module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  security_tooling_account_id = "111111111111"
  identity_account_id         = "222222222222"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_non_numeric_security_tooling_account_id" {
  command = plan

  variables {
    security_tooling_account_id = "bad"
  }

  expect_failures = [var.security_tooling_account_id]
}

run "rejects_bad_account_id_in_registrations" {
  command = plan

  variables {
    registrations = {
      "ssm.amazonaws.com" = "not-an-id"
    }
  }

  expect_failures = [var.registrations]
}
