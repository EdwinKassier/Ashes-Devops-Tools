# Variable-validation tests for the aws-security stage.
#
# Uses five mock providers so no AWS credentials are required. The accept case
# reaches (and passes) plan with a valid var set; the reject case fails the
# management_account_id validation before any resource is evaluated.

mock_provider "aws" {}
mock_provider "aws" { alias = "management" }
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  org_id                      = "o-abc1234567"
  org_root_id                 = "r-abc1"
  management_account_id       = "111111111111"
  security_tooling_account_id = "222222222222"
  log_archive_account_id      = "333333333333"
  shared_services_account_id  = "555555555555"
  forensics_account_id        = "444444444444"

  log_archive_bucket_name     = "ashes-org-log-archive"
  key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
  config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
  aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
  meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
  break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"

  notification_subscribers = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }
}

# The forensics CMK ARN flows into the incident-response module's
# forensics_kms_key_arn, whose count keys off whether that ARN is set. Under
# mock the CMK ARN is unknown at plan, which would make that count
# indeterminate; override the CMK output with a known ARN so plan can resolve.
override_module {
  target  = module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:444444444444:key/forensics-0000" }
}

run "valid_var_set_accepted" {
  # Accept case: a complete, valid var set must pass all validations and plan.
  command = plan
}

run "invalid_management_account_id_rejected" {
  # Reject case: a malformed (non-12-digit) management account ID must fail its
  # validation.
  command = plan

  variables {
    management_account_id = "not-an-account"
  }

  expect_failures = [var.management_account_id]
}

run "create_break_glass_without_principals_rejected" {
  command = plan

  variables {
    create_break_glass             = true
    break_glass_trusted_principals = []
  }

  expect_failures = [var.create_break_glass]
}

run "unknown_kms_key_user_target_rejected" {
  # Reject case: kms_key_user_arns may only target the three stage CMKs.
  command = plan

  variables {
    kms_key_user_arns = { audit = ["arn:aws:iam::333333333333:role/LogReader"] }
  }

  expect_failures = [var.kms_key_user_arns]
}

run "invalid_cloudtrail_s3_data_events_rejected" {
  command = plan

  variables {
    cloudtrail_s3_data_events = "objects"
  }

  expect_failures = [var.cloudtrail_s3_data_events]
}

run "rejects_malformed_key_admin_arn" {
  command = plan

  variables {
    key_admin_arn = "kms-admin"
  }

  expect_failures = [var.key_admin_arn]
}

run "rejects_wildcard_key_policy_admin_role_name" {
  command = plan

  variables {
    key_policy_admin_role_name = "break-*"
  }

  expect_failures = [var.key_policy_admin_role_name]
}
