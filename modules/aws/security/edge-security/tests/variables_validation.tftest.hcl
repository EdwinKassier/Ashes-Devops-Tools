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

run "rejects_vpc_origin_without_arn" {
  command = plan

  variables {
    enable_edge       = true
    enable_vpc_origin = true
  }

  expect_failures = [var.vpc_origin_arn]
}

run "rejects_regional_waf_without_resource" {
  command = plan

  variables {
    enable_regional_waf = true
  }

  expect_failures = [var.regional_waf_resource_arn]
}

run "rejects_unsupported_method_set" {
  command = plan

  variables {
    allowed_methods = ["GET", "POST"]
  }

  expect_failures = [var.allowed_methods]
}
