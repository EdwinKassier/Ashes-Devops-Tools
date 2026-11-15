# Variable-validation tests for the aws-workload stage.
#
# Two mock providers (default + us_east_1 alias). The accept case reaches plan
# with defaults + required vars; the reject case fails the vpc_cidr validation
# before any resource is evaluated.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  tgw_id                   = "tgw-000000000000abcd"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_archive_bucket_name  = "ashes-org-log-archive"
  # A real CMK so the (default-on) systems-manager module's kms_key_id validation
  # passes; the stage's own defaults are otherwise exercised.
  kms_key_arn = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

run "valid_var_set_accepted" {
  # Accept case: required vars + all defaults must pass validation and plan.
  command = plan
}

run "invalid_vpc_cidr_rejected" {
  # Reject case: a malformed CIDR must fail the vpc_cidr validation.
  command = plan

  variables {
    vpc_cidr = "not-a-cidr"
  }

  expect_failures = [var.vpc_cidr]
}

run "resolver_profile_id_must_be_a_profile_id" {
  command = plan

  variables {
    resolver_profile_id = "vpc-0123456789abcdef0"
  }

  expect_failures = [var.resolver_profile_id]
}

run "gateway_endpoint_policies_need_organization_id" {
  command = plan

  variables {
    enable_gateway_endpoint_policies = true
  }

  expect_failures = [var.organization_id]
}

run "organization_id_format_checked" {
  command = plan

  variables {
    organization_id = "org-123"
  }

  expect_failures = [var.organization_id]
}
