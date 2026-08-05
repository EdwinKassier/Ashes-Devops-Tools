# Variable validation tests for the aws/access-analyzer-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: the default analyzer names and unused_access_age must pass.
  command = plan
}

run "zero_unused_access_age_rejected" {
  # Reject case: unused_access_age = 0 must trip the >= 1 validation.
  command = plan

  variables {
    unused_access_age = 0
  }

  expect_failures = [var.unused_access_age]
}
