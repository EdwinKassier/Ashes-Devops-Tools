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

run "allowed_cidrs_must_be_cidrs" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    region        = "eu-west-2"
    org_id        = "o-abc1234567"
    allowed_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.allowed_cidrs]
}

run "unknown_endpoint_policy_mode_rejected" {
  command = plan

  variables {
    vpc_id               = "vpc-0123456789abcdef0"
    region               = "eu-west-2"
    org_id               = "o-abcde12345"
    endpoint_policy_mode = "org_resources"
  }

  expect_failures = [var.endpoint_policy_mode]
}
