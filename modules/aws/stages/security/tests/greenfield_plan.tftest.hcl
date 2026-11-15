# Greenfield plan of the aws-security stage: no override_module at all, so every
# CMK, bucket and topic ARN is unknown at plan exactly as on a first real plan.
# Any count or for_each that hangs off one of those ARNs fails here with
# "Invalid count argument". The other suites override the CMKs with known ARNs
# and cannot catch that.

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
  aws = {
    log_archive_bucket_name     = "ashes-org-log-archive"
    key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
    config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
    aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
    break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"
    enable_incident_response    = true
    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}

run "plans_with_unknown_cmk_arns" {
  command = plan

  # The forensics CMK is created in this plan, so its ARN is unknown; the
  # forensics role's KMS grant must still be planned.
  assert {
    condition     = module.incident_response.forensics_kms_grant_enabled
    error_message = "The forensics role must get its KMS grant on the forensics CMK created in the same plan"
  }
}
