# Variable validation tests for the aws/config-org module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  recorder_only       = false
  config_role_arn     = "arn:aws:iam::111111111111:role/config"
  aggregator_role_arn = "arn:aws:iam::111111111111:role/config-agg"
  log_archive_bucket  = "ashes-org-log-archive"
}

run "defaults_accepted" {
  # Accept case: the required ARNs and bucket with default Region set must pass.
  command = plan
}

run "empty_log_archive_bucket_rejected" {
  # Reject case: a blank log-archive bucket name must trip the non-empty validation.
  command = plan

  variables {
    log_archive_bucket = ""
  }

  expect_failures = [var.log_archive_bucket]
}

run "malformed_config_role_arn_rejected" {
  command = plan

  variables {
    config_role_arn = "not-an-arn"
  }

  expect_failures = [var.config_role_arn]
}

run "malformed_aggregator_role_arn_rejected" {
  command = plan

  variables {
    aggregator_role_arn = "not-an-arn"
  }

  expect_failures = [var.aggregator_role_arn]
}
