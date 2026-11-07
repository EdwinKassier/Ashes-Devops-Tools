# Access Analyzer coverage in the aws-security stage. module.access_analyzer is NOT
# overridden here (plan_assertions overrides it), so the real analyzers plan
# under mock_provider.

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
    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}

# Feed known outputs for the children whose outputs flow into other children or
# into stage outputs, so assertions are non-vacuous under mock.
override_module {
  target  = module.log_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:333333333333:key/log-cmk-0000" }
}

override_module {
  target  = module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:444444444444:key/forensics-0000" }
}

# Security-tooling CMK: created in the security-tooling account so the SNS topic
# and SSM sessions there can actually use it (the log CMK is cross-account and
# would deny them).
override_module {
  target  = module.sectool_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:222222222222:key/sectool-0000" }
}

override_module {
  target = module.log_archive_bucket
  outputs = {
    bucket_arn  = "arn:aws:s3:::ashes-org-log-archive"
    bucket_name = "ashes-org-log-archive"
  }
}

override_module {
  target  = module.guardduty
  outputs = { detector_ids = { "eu-west-2" = "det-eu-west-2-0000" } }
}

override_module {
  target  = module.securityhub
  outputs = { configuration_policy_id = "cfg-policy-uuid-0000" }
}

override_module {
  target  = module.config
  outputs = { aggregator_arn = "arn:aws:config:eu-west-2:222222222222:config-aggregator/agg-0000" }
}

override_module {
  target  = module.security_notifications
  outputs = { topic_arn = "arn:aws:sns:eu-west-2:222222222222:security-notifications" }
}

# The remaining children create resources whose mock-generated attributes fail
# AWS-side format validation under `command = apply` (e.g. patch-baseline IDs,
# IAM role ARNs). They produce no cross-child or asserted outputs, so override
# them out to keep the apply clean while still exercising their wiring.
override_module {
  target = module.cloudtrail
  outputs = {
    cloudwatch_log_group_name = "/aws/cloudtrail/org-trail"
    cis_alarm_sns_topic_arn   = "arn:aws:sns:eu-west-2:111111111111:org-trail-cis-alarms"
  }
}
override_module { target = module.delegated_admin }
override_module { target = module.org_security_service }
override_module { target = module.securitylake }
override_module { target = module.systems_manager }
override_module { target = module.incident_response }
override_module { target = module.service_quotas }

run "analyzers_in_every_non_home_region" {
  command = plan

  variables {
    aws_region = "eu-west-2"
    aws = {
      log_archive_bucket_name     = "ashes-org-log-archive"
      key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
      config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
      aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
      meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
      break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"
      aws_enabled_regions         = ["eu-west-2", "eu-west-1", "us-east-1"]
    }
  }

  assert {
    condition     = toset(keys(module.access_analyzer.external_analyzer_arns_by_region)) == toset(["eu-west-1", "us-east-1"])
    error_message = "external analyzers must be planned in every non-home enabled region"
  }
}

run "internal_analyzer_on_by_default" {
  command = plan

  assert {
    condition     = var.aws.enable_internal_access_analyzer == true
    error_message = "the internal-access analyzer is on by default (new resources on upgrade)"
  }
}
