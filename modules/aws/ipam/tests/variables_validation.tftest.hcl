# Variable validation tests for the aws/ipam module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # The defaults plus a valid org_arn must pass all validations.
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
  }
}

run "bad_top_cidr_rejected" {
  # A malformed top_cidr must trip the cidrhost-based validation.
  command = plan

  variables {
    org_arn  = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
    top_cidr = "not-a-cidr"
  }

  expect_failures = [var.top_cidr]
}
