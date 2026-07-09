# Variable-validation tests for the aws-network-hub stage.
#
# A single mock provider. The accept case reaches (and passes) plan with the
# defaults + required vars; the reject case fails the org_arn validation before
# any resource is evaluated.

mock_provider "aws" {}

variables {
  org_id                   = "o-abc1234567"
  org_arn                  = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
}

run "valid_var_set_accepted" {
  # Accept case: required vars + all defaults must pass validation and plan.
  command = plan
}

run "invalid_org_arn_rejected" {
  # Reject case: a non-Organizations ARN must fail the org_arn validation.
  command = plan

  variables {
    org_arn = "arn:aws:iam::111111111111:role/not-an-org"
  }

  expect_failures = [var.org_arn]
}
