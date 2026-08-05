# Variable validation tests for the aws/vpc module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Defaults plus the required flow_log_destination_arn must pass validation.
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }
}

run "bad_cidr_block_rejected" {
  # A malformed cidr_block must trip the cidrnetmask-based validation.
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    cidr_block               = "not-a-cidr"
  }

  expect_failures = [var.cidr_block]
}
