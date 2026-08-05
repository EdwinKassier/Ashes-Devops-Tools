# Variable validation tests for the aws/securityhub-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

run "defaults_accepted" {
  # Accept case: valid ids plus module defaults must pass all validations.
  command = plan

  variables {
    security_tooling_account_id = "111111111111"
    org_root_id                 = "r-abc1"
  }
}

run "bad_account_id_rejected" {
  # Reject case: a non-12-digit account id must trip the regex validation.
  command = plan

  variables {
    security_tooling_account_id = "123"
    org_root_id                 = "r-abc1"
  }

  expect_failures = [var.security_tooling_account_id]
}
