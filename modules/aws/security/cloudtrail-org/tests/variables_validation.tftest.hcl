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

run "invalid_s3_data_events_rejected" {
  command = plan

  variables {
    log_archive_bucket        = "sra-log-archive-bucket"
    kms_key_arn               = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    cloudtrail_s3_data_events = "everything"
  }

  expect_failures = [var.cloudtrail_s3_data_events]
}

run "unknown_cis_alarm_key_rejected" {
  command = plan

  variables {
    log_archive_bucket  = "sra-log-archive-bucket"
    kms_key_arn         = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    cis_alarms_excluded = ["not-a-cis-alarm"]
  }

  expect_failures = [var.cis_alarms_excluded]
}

run "invalid_retention_rejected" {
  command = plan

  variables {
    log_archive_bucket             = "sra-log-archive-bucket"
    kms_key_arn                    = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    cloudwatch_logs_retention_days = 42
  }

  expect_failures = [var.cloudwatch_logs_retention_days]
}

run "non_role_key_manager_rejected" {
  command = plan

  variables {
    log_archive_bucket                   = "sra-log-archive-bucket"
    kms_key_arn                          = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    cloudwatch_logs_kms_key_manager_arns = ["arn:aws:iam::111111111111:user/alice"]
  }

  expect_failures = [var.cloudwatch_logs_kms_key_manager_arns]
}
