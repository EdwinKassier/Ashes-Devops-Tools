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

run "self_logging_target_rejected" {
  command = plan

  variables {
    access_log_bucket = "acme-org-log-archive"
  }

  expect_failures = [var.access_log_bucket]
}

run "bad_cloudtrail_trail_account_id_rejected" {
  command = plan

  variables {
    cloudtrail_trail_account_id = "12345"
  }

  expect_failures = [var.cloudtrail_trail_account_id]
}

run "zero_access_log_retention_rejected" {
  command = plan

  variables {
    access_log_retention_days = 0
  }

  expect_failures = [var.access_log_retention_days]
}

run "overlong_derived_access_log_bucket_name_rejected" {
  command = plan

  variables {
    log_archive_bucket_name = "acme-org-log-archive-with-a-very-long-name-0000000001"
  }

  expect_failures = [aws_s3_bucket.access_logs]
}
