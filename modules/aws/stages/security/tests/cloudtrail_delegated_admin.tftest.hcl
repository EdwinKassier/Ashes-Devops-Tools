# Organization trail managed by the CloudTrail delegated administrator.
#
# Each aliased mock provider stamps its own marker on the trail ARN it plans
# (mock_resource, override_during = plan), so an assertion on the stage output
# shows which provider created the trail. The management account owns the
# trail either way; the marker only identifies the creating provider.
# module.cloudtrail_delegated_admin and module.delegated_admin are NOT
# overridden, so their real resources plan under mock.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
  mock_resource "aws_cloudtrail" {
    override_during = plan
    defaults        = { arn = "arn:aws:cloudtrail:eu-west-2:111111111111:trail/created-by-management-provider" }
  }
}

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
  mock_resource "aws_cloudtrail" {
    override_during = plan
    defaults        = { arn = "arn:aws:cloudtrail:eu-west-2:111111111111:trail/created-by-security-tooling-provider" }
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
    log_archive_bucket_name           = "ashes-org-log-archive"
    key_admin_arn                     = "arn:aws:iam::333333333333:role/kms-admin"
    config_role_arn                   = "arn:aws:iam::222222222222:role/aws-config-role"
    aggregator_role_arn               = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    meta_store_manager_role_arn       = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
    break_glass_role_arn              = "arn:aws:iam::111111111111:role/break-glass"
    cloudtrail_cloudwatch_role_arn    = "arn:aws:iam::111111111111:role/org-trail-cloudwatch-delivery"
    enable_cloudtrail_delegated_admin = true
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

override_module { target = module.access_analyzer }
override_module { target = module.org_security_service }
override_module { target = module.securitylake }
override_module { target = module.systems_manager }
override_module { target = module.incident_response }
override_module { target = module.service_quotas }

run "trail_created_by_security_tooling_provider" {
  command = plan

  assert {
    condition = (
      output.delegated_admin_trail_arn == "arn:aws:cloudtrail:eu-west-2:111111111111:trail/created-by-security-tooling-provider" &&
      module.cloudtrail_delegated_admin[0].trail_name == "org-trail-delegated"
    )
    error_message = "The delegated-admin trail must be planned by the security-tooling provider, under its own name."
  }

  # CloudTrail needs the log group (and its role) in the calling account: the
  # stage's log-group output now points at the security-tooling group.
  assert {
    condition     = output.cloudtrail_log_group_name == "/aws/cloudtrail/org-trail-delegated"
    error_message = "The CloudWatch Logs group must belong to the delegated-admin trail."
  }

  # No window without an org trail: the management-account trail stays in
  # configuration (Terraform does not destroy it) until the runbook retires it.
  assert {
    condition     = length(module.cloudtrail) == 1 && module.cloudtrail[0].trail_name == "org-trail"
    error_message = "The management-account trail must stay in configuration during the migration."
  }

  # aws-organization owns the registration; aws-security drops it.
  assert {
    condition = (
      !contains(module.delegated_admin.registered_services, "cloudtrail.amazonaws.com") &&
      contains(module.delegated_admin.registered_services, "config.amazonaws.com")
    )
    error_message = "aws-security must leave the cloudtrail.amazonaws.com registration to aws-organization."
  }
}

run "management_trail_retired_after_break_glass" {
  command = plan

  variables {
    aws = merge(var.aws, { create_management_trail = false })
  }

  assert {
    condition     = length(module.cloudtrail) == 0 && length(module.cloudtrail_delegated_admin) == 1
    error_message = "create_management_trail = false must drop only the management-account trail."
  }
}

run "default_is_unchanged" {
  command = plan

  variables {
    aws = merge(var.aws, { enable_cloudtrail_delegated_admin = false, create_management_trail = false })
  }

  assert {
    condition = (
      length(module.cloudtrail_delegated_admin) == 0 &&
      length(module.cloudtrail) == 1 &&
      output.delegated_admin_trail_arn == null &&
      contains(module.delegated_admin.registered_services, "cloudtrail.amazonaws.com")
    )
    error_message = "With the flag off the management trail and the cloudtrail registration must be unchanged (create_management_trail is ignored)."
  }
}
