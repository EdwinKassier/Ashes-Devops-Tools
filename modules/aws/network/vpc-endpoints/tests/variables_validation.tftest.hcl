# Variable validation tests for the aws/vpc-endpoints module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Required inputs plus defaults must pass validation.
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    region = "eu-west-2"
    org_id = "o-abcde12345"
  }
}

run "empty_org_id_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    region = "eu-west-2"
    org_id = ""
  }

  expect_failures = [var.org_id]
}

run "bad_region_rejected" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    region = "not-a-region"
    org_id = "o-abcde12345"
  }

  expect_failures = [var.region]
}
