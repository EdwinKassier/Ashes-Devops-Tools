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
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
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
