# Variable validation tests for the aws/cloudtrail-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: the default trail_name plus required inputs must pass.
  command = plan

  variables {
    log_archive_bucket = "sra-log-archive-bucket"
    kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }
}

run "empty_trail_name_rejected" {
  # Reject case: a blank trail_name must trip the non-empty validation.
  command = plan

  variables {
    trail_name         = ""
    log_archive_bucket = "sra-log-archive-bucket"
    kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.trail_name]
}
