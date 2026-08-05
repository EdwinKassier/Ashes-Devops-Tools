# Variable validation tests for the aws/edge-security module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_blank_name_prefix" {
  command = plan

  variables {
    name_prefix = "  "
  }

  expect_failures = [var.name_prefix]
}
