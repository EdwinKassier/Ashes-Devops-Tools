# Variable validation tests for the aws/organization module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: the SRA defaults must pass all validations.
  command = plan
}

run "empty_ou_name_rejected" {
  # Reject case: a blank top-level OU name must trip the non-empty validation.
  command = plan

  variables {
    top_level_ous = [""]
  }

  expect_failures = [var.top_level_ous]
}
