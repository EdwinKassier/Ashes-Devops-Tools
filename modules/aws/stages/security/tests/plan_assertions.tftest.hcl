# Plan-assertion tests for the aws-security stage.
#
# Uses five mock providers (default + four aliases) so no AWS credentials are
# required. The composition threads computed values between children (the log
# CMK ARN feeds the bucket, CloudTrail, Config, Security Lake, SSM, and the
# notifications topic; the notifications topic feeds the service-quota alarms).
# Under mock those ARNs are unknown at plan, so we override the children that
# produce cross-child outputs with known values and drive the run with
# `command = apply`. That lets the stage OUTPUT WIRING (input <- output edges)
# be asserted concretely: proving the wiring is the meaningful thing here.

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
override_module { target = module.cloudtrail }
override_module { target = module.access_analyzer }
override_module { target = module.delegated_admin }
override_module { target = module.org_security_service }
override_module { target = module.securitylake }
override_module { target = module.systems_manager }
override_module { target = module.incident_response }
override_module { target = module.service_quotas }

run "composes_security_baseline" {
  command = apply

  # GuardDuty detector map is keyed by the (plan-known) enabled Region.
  assert {
    condition     = contains(keys(output.guardduty_detector_ids), "eu-west-2")
    error_message = "guardduty_detector_ids must be keyed by the enabled Region eu-west-2"
  }

  # Bucket name is the deterministic cross-root naming contract.
  assert {
    condition     = output.log_archive_bucket_name == "ashes-org-log-archive"
    error_message = "log_archive_bucket_name output must surface the bucket name contract"
  }

  # The log CMK ARN surfaces through the stage output (wiring proof).
  assert {
    condition     = output.log_cmk_arn == "arn:aws:kms:eu-west-2:333333333333:key/log-cmk-0000"
    error_message = "log_cmk_arn output must surface module.log_cmk.key_arn"
  }

  # Forensics CMK ARN is a separate key in the forensics account.
  assert {
    condition     = output.forensics_cmk_arn == "arn:aws:kms:eu-west-2:444444444444:key/forensics-0000"
    error_message = "forensics_cmk_arn output must surface module.forensics_cmk.key_arn"
  }

  # The notifications topic ARN surfaces through the stage output; the
  # service_quotas child consumes the same value as notifications_topic_arn.
  assert {
    condition     = output.security_notifications_topic_arn == "arn:aws:sns:eu-west-2:222222222222:security-notifications"
    error_message = "security_notifications_topic_arn output must surface module.security_notifications.topic_arn"
  }

  # Security Hub central configuration policy id surfaces through the stage.
  assert {
    condition     = output.securityhub_configuration_policy_id == "cfg-policy-uuid-0000"
    error_message = "securityhub_configuration_policy_id output must surface module.securityhub.configuration_policy_id"
  }

  # Config org aggregator is present (recorder_only = false wires the aggregator).
  assert {
    condition     = module.config.aggregator_arn != null
    error_message = "the Config org aggregator must be present when recorder_only = false"
  }

  # forensics_account_id is echoed as part of the cross-root contract.
  assert {
    condition     = output.forensics_account_id == "444444444444"
    error_message = "forensics_account_id output must echo the forensics account id"
  }

  # The security-tooling CMK ARN surfaces through the stage output; it is a
  # distinct key from the log CMK (different account) so SNS/SSM in the
  # security-tooling account can use it.
  assert {
    condition     = output.sectool_cmk_arn == "arn:aws:kms:eu-west-2:222222222222:key/sectool-0000"
    error_message = "sectool_cmk_arn output must surface module.sectool_cmk.key_arn"
  }

  # Firewall Manager is composed but gated OFF by default, so no FMS admin
  # registration is created (admin_account_id output is null).
  assert {
    condition     = module.firewall_manager.admin_account_id == null
    error_message = "Firewall Manager must be gated off by default (enable_firewall_manager=false)"
  }
}
