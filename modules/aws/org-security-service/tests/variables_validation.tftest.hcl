# Variable validation tests for the aws/org-security-service module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  enabled_services            = ["macie", "inspector"]
  security_tooling_account_id = "111111111111"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_unknown_service" {
  command = plan

  variables {
    enabled_services = ["macie", "bogus"]
  }

  expect_failures = [var.enabled_services]
}

run "rejects_non_numeric_account_id" {
  command = plan

  variables {
    security_tooling_account_id = "bad"
  }

  expect_failures = [var.security_tooling_account_id]
}
