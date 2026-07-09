# Variable validation tests for the aws/log-archive-bucket module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

variables {
  log_archive_bucket_name = "acme-org-log-archive"
  kms_key_arn             = "arn:aws:kms:eu-west-1:111122223333:key/abcd-1234"
  org_id                  = "o-abc123xyz0"
}

run "defaults_accepted" {
  # Accept case: defaults (COMPLIANCE, 365 days) pass all validations.
  command = plan
}

run "invalid_object_lock_mode_rejected" {
  # Reject case: an unknown Object Lock mode must trip the validation.
  command = plan

  variables {
    object_lock_mode = "BOGUS"
  }

  expect_failures = [var.object_lock_mode]
}
