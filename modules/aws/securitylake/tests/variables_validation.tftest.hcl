# Variable validation tests for the aws/securitylake module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  meta_store_manager_role_arn = "arn:aws:iam::111111111111:role/AmazonSecurityLakeMetaStoreManager"
  kms_key_id                  = "arn:aws:kms:eu-west-2:111111111111:key/abc"
}

run "defaults_are_valid" {
  command = plan
}

run "rejects_unknown_log_source" {
  command = plan

  variables {
    log_sources = ["CLOUD_TRAIL_MGMT", "BOGUS_SOURCE"]
  }

  expect_failures = [var.log_sources]
}

run "rejects_missing_meta_store_role_when_enabled" {
  command = plan

  variables {
    meta_store_manager_role_arn = ""
  }

  expect_failures = [var.meta_store_manager_role_arn]
}

run "rejects_bad_subscriber_principal" {
  command = plan

  variables {
    subscriber_principal = "not-an-account"
  }

  expect_failures = [var.subscriber_principal]
}
