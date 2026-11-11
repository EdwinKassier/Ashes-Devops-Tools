# Wiring tests for the aws-security stage: the critical children (log-archive
# bucket, organization CloudTrail, Config) are NOT overridden. They plan for
# real under mock providers, so each assertion checks a child output that the
# child computes from what the stage passed in. A wrong or dropped argument in
# main.tf fails these runs; an override_module would hide it.
#
# Only the three CMKs are overridden: their key ARNs are unknown at plan under
# mock, and the assertions here are about the consumers, not the keys.

mock_provider "aws" {}
mock_provider "aws" { alias = "management" }
mock_provider "aws" {
  alias = "security_tooling"
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  # Roles created in security tooling get a known ARN at plan, so the
  # aggregator-role wiring below is checkable.
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::222222222222:role/created-in-security-tooling" }
  }
}
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
    log_archive_bucket_name     = "acme-wiring-log-archive"
    key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
    break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"
    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}

override_module {
  target  = module.log_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:333333333333:key/log-cmk-0000" }
}

override_module {
  target  = module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:444444444444:key/forensics-0000" }
}

override_module {
  target  = module.sectool_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:222222222222:key/sectool-0000" }
}

run "log_archive_and_config_wiring" {
  command = plan

  # log_archive_bucket_name reaches the bucket child; the bucket child's name
  # output is what CloudTrail and Config receive.
  assert {
    condition     = module.log_archive_bucket.bucket_name == "acme-wiring-log-archive" && output.log_archive_bucket_name == "acme-wiring-log-archive"
    error_message = "aws.log_archive_bucket_name must reach module.log_archive_bucket."
  }

  # With no config_role_arn the Config child builds the service-linked role ARN
  # from the account_id the stage passes (security_tooling_account_id).
  assert {
    condition     = module.config.config_role_arn == "arn:aws:iam::222222222222:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "the stage must pass security_tooling_account_id to module.config as account_id."
  }

  # recorder_only = false and no aggregator_role_arn: Config creates the org
  # aggregator role in security tooling and wires it to the aggregator.
  assert {
    condition     = module.config.aggregator_role_arn == "arn:aws:iam::222222222222:role/created-in-security-tooling"
    error_message = "the stage must run Config with the org aggregator (recorder_only = false)."
  }
}

run "enabled_regions_reach_config_and_guardduty" {
  command = plan

  variables {
    aws = merge(var.aws, {
      aws_enabled_regions = ["eu-west-2", "eu-west-1"]
    })
  }

  # Security Lake is overridden here only: the aws provider allows one
  # configuration block per aws_securitylake_data_lake, so the securitylake
  # child cannot plan two Regions (a separate defect of that module).
  override_module {
    target = module.securitylake
  }

  # One recorder and one detector per enabled Region.
  assert {
    condition     = toset(keys(module.config.recorder_names)) == toset(["eu-west-2", "eu-west-1"])
    error_message = "aws.aws_enabled_regions must reach module.config (one recorder per Region)."
  }

  assert {
    condition     = toset(keys(output.guardduty_detector_ids)) == toset(["eu-west-2", "eu-west-1"])
    error_message = "aws.aws_enabled_regions must reach module.guardduty (one detector per Region)."
  }
}

run "explicit_config_roles_reach_config" {
  command = plan

  variables {
    aws = merge(var.aws, {
      config_role_arn     = "arn:aws:iam::222222222222:role/aws-config-role"
      aggregator_role_arn = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    })
  }

  assert {
    condition     = module.config.config_role_arn == "arn:aws:iam::222222222222:role/aws-config-role" && module.config.aggregator_role_arn == "arn:aws:iam::222222222222:role/aws-config-aggregator"
    error_message = "aws.config_role_arn and aws.aggregator_role_arn must reach module.config."
  }
}

run "cloudtrail_wiring" {
  command = plan

  variables {
    aws = merge(var.aws, {
      cloudwatch_logs_kms_key_arn    = "arn:aws:kms:eu-west-2:111111111111:key/cw-logs-0000"
      cloudtrail_alarm_sns_topic_arn = "arn:aws:sns:eu-west-2:111111111111:existing-cis-alarms"
      cloudtrail_cis_alarms_excluded = ["root-account-usage"]
    })
  }

  # Supplied CloudWatch Logs CMK and alarm topic are used as given, and the
  # stage surfaces the child's topic.
  assert {
    condition     = module.cloudtrail[0].cloudwatch_logs_kms_key_arn == "arn:aws:kms:eu-west-2:111111111111:key/cw-logs-0000"
    error_message = "aws.cloudwatch_logs_kms_key_arn must reach module.cloudtrail."
  }

  assert {
    condition     = module.cloudtrail[0].cis_alarm_sns_topic_arn == "arn:aws:sns:eu-west-2:111111111111:existing-cis-alarms" && output.cis_alarm_sns_topic_arn == "arn:aws:sns:eu-west-2:111111111111:existing-cis-alarms"
    error_message = "aws.cloudtrail_alarm_sns_topic_arn must reach module.cloudtrail and the stage output."
  }

  # cis_alarms_excluded reaches the child: the excluded filter is not planned,
  # the others are.
  assert {
    condition     = !contains(keys(module.cloudtrail[0].cis_metric_filter_patterns), "root-account-usage") && contains(keys(module.cloudtrail[0].cis_metric_filter_patterns), "unauthorized-api-calls")
    error_message = "aws.cloudtrail_cis_alarms_excluded must reach module.cloudtrail."
  }

  # The trail's CloudWatch Logs group is planned (enable_cloudwatch_logs on by
  # default) and surfaced by the stage.
  assert {
    condition     = output.cloudtrail_log_group_name == module.cloudtrail[0].cloudwatch_log_group_name && startswith(output.cloudtrail_log_group_name, "/aws/cloudtrail/")
    error_message = "the stage must surface the trail's CloudWatch Logs group."
  }
}

run "cloudwatch_logs_off_reaches_cloudtrail" {
  command = plan

  variables {
    aws = merge(var.aws, {
      enable_cloudwatch_logs = false
    })
  }

  assert {
    condition     = length(module.cloudtrail[0].cis_metric_filter_patterns) == 0 && output.cloudtrail_log_group_name == null
    error_message = "aws.enable_cloudwatch_logs = false must reach module.cloudtrail (no log group, no CIS filters)."
  }
}
