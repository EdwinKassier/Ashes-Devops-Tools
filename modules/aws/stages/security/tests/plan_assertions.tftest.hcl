# Plan-assertion tests for the aws-security stage.
#
# Uses five mock providers (default + four aliases) so no AWS credentials are
# required. The composition threads computed values between children (the log
# CMK ARN feeds the bucket, CloudTrail, Config, Security Lake, SSM, and the
# notifications topic; the notifications topic feeds the service-quota alarms).
# Under mock those ARNs are unknown at plan, so we override the children that
# produce cross-child outputs with known values and drive the run with
# `command = apply`. Overridden children discard their inputs, so the
# input-to-child wiring is asserted in wiring.tftest.hcl instead, where the
# log-archive bucket, CloudTrail and Config plan for real.

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
override_module { target = module.access_analyzer }
override_module { target = module.delegated_admin }
override_module { target = module.org_security_service }
override_module { target = module.securitylake }
override_module { target = module.systems_manager }
override_module { target = module.incident_response }
override_module { target = module.service_quotas }

run "composes_security_baseline" {
  # What each child computes from the stage inputs is asserted in
  # wiring.tftest.hcl, where the critical children plan for real. This run
  # applies the whole composition with the cross-child producers overridden.
  command = apply

  assert {
    condition     = var.aws.enable_cloudwatch_logs == true && var.aws.cloudtrail_s3_data_events == "write"
    error_message = "CIS 4.x alarms and S3 write data events (CIS 3.8) must be on by default"
  }

  # Each stage output is wired to the right child. The overridden children
  # return distinct values, so swapping two outputs fails this check.
  assert {
    condition = (
      output.log_cmk_arn == module.log_cmk.key_arn &&
      output.forensics_cmk_arn == module.forensics_cmk.key_arn &&
      output.sectool_cmk_arn == module.sectool_cmk.key_arn &&
      output.security_notifications_topic_arn == module.security_notifications.topic_arn &&
      output.securityhub_configuration_policy_id == module.securityhub.configuration_policy_id &&
      length(distinct([output.log_cmk_arn, output.forensics_cmk_arn, output.sectool_cmk_arn])) == 3
    )
    error_message = "each CMK, topic and policy output must come from its own child module"
  }

  # Firewall Manager is composed but gated OFF by default, so no FMS admin
  # registration is created (admin_account_id output is null).
  assert {
    condition     = module.firewall_manager.admin_account_id == null
    error_message = "Firewall Manager must be gated off by default (enable_firewall_manager=false)"
  }
}

# Managed break-glass role: when create_break_glass is true, the stage
# creates the role and the assumption alarm watches the stage-created ARN, not an
# external string.
run "managed_break_glass_is_created_and_watched" {
  command = plan

  variables {
    aws = merge(var.aws, {
      create_break_glass             = true
      break_glass_trusted_principals = ["arn:aws:iam::111111111111:role/IncidentCommander"]
      break_glass_role_arn           = "" # not used when creating
    })
  }

  # Make the created role's ARN known at plan so the wiring assertion is non-vacuous.
  override_module {
    target = module.break_glass[0]
    outputs = {
      role_arns            = {}
      break_glass_role_arn = "arn:aws:iam::111111111111:role/OrganizationBreakGlass"
    }
  }

  # The break-glass role module is instantiated.
  assert {
    condition     = length(module.break_glass) == 1
    error_message = "create_break_glass = true must instantiate the managed break-glass role."
  }

  # The effective ARN wired to the alarm is the created role's ARN, not the
  # (empty) external string.
  assert {
    condition     = local.effective_break_glass_role_arn == "arn:aws:iam::111111111111:role/OrganizationBreakGlass"
    error_message = "the assumption alarm must watch the stage-created break-glass role ARN."
  }
}

# Default identities: with no key_admin / Config role ARNs the stage grants each
# CMK's own-account tfc-apply role key administration and lets config-org create
# the Config service-linked role and the org aggregator role.
run "default_operator_roles" {
  command = plan

  variables {
    aws = merge(var.aws, {
      key_admin_arn       = null
      config_role_arn     = null
      aggregator_role_arn = null
    })
  }

  assert {
    condition = local.key_admin_arns == {
      log_archive      = "arn:aws:iam::333333333333:role/tfc-apply"
      forensics        = "arn:aws:iam::444444444444:role/tfc-apply"
      security_tooling = "arn:aws:iam::222222222222:role/tfc-apply"
    }
    error_message = "key_admin_arn = null must default each CMK's admin to its own account's tfc-apply role."
  }
}

# The pipeline key admin must not hold kms:PutKeyPolicy — each CMK's policy
# admin defaults to the member break-glass role in the key's OWN account
# (PutKeyPolicy is not cross-account), and is never the key admin.
run "key_policy_admin_defaults_to_member_break_glass" {
  command = plan

  variables {
    aws = merge(var.aws, {
      key_admin_arn = null
    })
  }

  assert {
    condition = (
      local.key_policy_admin_arns["log_archive"] == tolist(["arn:aws:iam::333333333333:role/break-glass"]) &&
      local.key_policy_admin_arns["forensics"] == tolist(["arn:aws:iam::444444444444:role/break-glass"]) &&
      local.key_policy_admin_arns["security_tooling"] == tolist(["arn:aws:iam::222222222222:role/break-glass"])
    )
    error_message = "each CMK's PutKeyPolicy holder must default to the break-glass role in the key's own account"
  }

  assert {
    condition     = alltrue([for k, a in local.key_policy_admin_arns : !contains(a, local.key_admin_arns[k])])
    error_message = "the pipeline key admin must never be the key-policy admin"
  }
}

run "key_policy_admin_legacy_opt_out" {
  command = plan

  variables {
    key_policy_admin_role_name = null
  }

  assert {
    condition     = alltrue([for a in values(local.key_policy_admin_arns) : length(a) == 0])
    error_message = "key_policy_admin_role_name = null must fall back to the legacy (key admin) behaviour"
  }
}

run "explicit_key_admin_wins" {
  command = plan

  assert {
    condition     = alltrue([for a in values(local.key_admin_arns) : a == "arn:aws:iam::333333333333:role/kms-admin"])
    error_message = "An explicit key_admin_arn must be used for every CMK."
  }
}

# Boundary propagation (tfc-oidc-baseline): roles the stage creates in the
# security-tooling account (Config aggregator, IR roles) carry that account's
# tfc-apply-boundary, derived from the security_tooling provider.
run "security_tooling_roles_carry_tfc_apply_boundary" {
  command = plan

  variables {
    aws = merge(var.aws, {
      aggregator_role_arn = null
    })
  }

  override_data {
    target = data.aws_caller_identity.security_tooling[0]
    values = { account_id = "222222222222" }
  }

  override_data {
    target = data.aws_partition.security_tooling[0]
    values = { partition = "aws" }
  }

  assert {
    condition     = local.security_tooling_boundary_arn == "arn:aws:iam::222222222222:policy/tfc-apply-boundary"
    error_message = "The security-tooling boundary ARN (passed to config + incident_response) must be derived from the security_tooling provider."
  }
}

run "security_tooling_boundary_disabled_with_null_name" {
  command = plan

  variables {
    tfc_apply_boundary_policy_name = null
  }

  assert {
    condition     = local.security_tooling_boundary_arn == null && length(data.aws_caller_identity.security_tooling) == 0
    error_message = "tfc_apply_boundary_policy_name = null must disable the boundary and skip the identity lookup."
  }
}

# Control Tower (or another owner) runs the org trail: no second trail here.
run "organization_trail_can_be_owned_elsewhere" {
  command = plan

  variables {
    aws = merge(var.aws, {
      create_organization_trail = false
    })
  }

  assert {
    condition     = length(module.cloudtrail) == 0 && output.cloudtrail_log_group_name == null
    error_message = "create_organization_trail = false must not create the org trail."
  }
}

# With no metastore role supplied, the stage creates it (default production
# profile no longer needs a hand-made prerequisite).
run "security_lake_creates_meta_store_role" {
  command = plan

  variables {
    aws = merge(var.aws, {
      meta_store_manager_role_arn = ""
    })
  }

  assert {
    condition = (
      length(aws_iam_role.securitylake_meta_store) == 1 &&
      jsondecode(aws_iam_role.securitylake_meta_store[0].assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com" &&
      endswith(aws_iam_role_policy_attachment.securitylake_meta_store[0].policy_arn, ":policy/service-role/AmazonSecurityLakeMetastoreManager")
    )
    error_message = "an empty meta_store_manager_role_arn must create the Security Lake metastore role."
  }
}

run "sectool_cmk_allows_eventbridge_to_publish_alerts" {
  command = plan

  assert {
    condition     = contains(local.sectool_cmk_service_principals, "events.amazonaws.com")
    error_message = "The security-tooling CMK must grant events.amazonaws.com, or EventBridge cannot publish sec-notify-* alerts to the encrypted security-notifications topic."
  }
}
