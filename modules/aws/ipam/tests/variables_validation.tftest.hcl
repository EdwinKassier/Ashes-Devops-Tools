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

run "regional_cidr_key_outside_enabled_regions_rejected" {
  # A regional_cidrs key that is not an operating region must trip the
  # key-membership validation.
  command = plan

  variables {
    org_arn             = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
    aws_enabled_regions = ["eu-west-2"]
    regional_cidrs = {
      eu-west-2 = "10.0.0.0/12"
      us-east-1 = "10.16.0.0/12"
    }
  }

  expect_failures = [var.regional_cidrs]
}
