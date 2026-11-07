# Config recorder migration for the aws-organization stage: the org-wide
# recorder StackSet (every member account except security tooling), the
# management account's direct recorder, and the recorder SCP. All three are
# off by default, because their delivery targets come from aws-security, which
# applies after aws-organization (docs/runbooks/aws-config-recorder-migration.md).
#
# Uses mock_provider; module.organization and module.account are overridden so
# the OU, root and account IDs are plan-known.

mock_provider "aws" {}

variables {
  terraform_run_role_arn   = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn     = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name  = "sra-log-archive-111111111111"
  tfc_organization         = "acme"
  github_federation_owners = ["acme"]
  guard_alert_emails       = ["secops@example.com"]
}

override_module {
  target = module.organization
  outputs = {
    organization_id       = "o-abc1234567"
    organization_arn      = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    roots_id              = "r-abcd"
    management_account_id = "111111111111"
    ou_ids = {
      "Security"          = "ou-abcd-security0"
      "Infrastructure"    = "ou-abcd-infra0000"
      "Workloads"         = "ou-abcd-workload0"
      "Sandbox"           = "ou-abcd-sandbox00"
      "Suspended"         = "ou-abcd-suspend00"
      "PolicyStaging"     = "ou-abcd-policyst0"
      "Exceptions"        = "ou-abcd-except000"
      "Transitional"      = "ou-abcd-transit00"
      "Workloads/Prod"    = "ou-abcd-prod0000"
      "Workloads/NonProd" = "ou-abcd-nonprod0"
    }
  }
}

# tfc-management-roles reads the partition / caller identity; mocks return
# random strings the provider's ARN validators reject, so pin real shapes.
override_data {
  target = module.tfc_management_roles[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.tfc_management_roles[0].data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

# Guard-alert ARNs are computed; pin them so the policies are plan-known.
override_resource {
  target          = aws_sns_topic.guard_alerts
  override_during = plan
  values          = { arn = "arn:aws:sns:us-east-1:111111111111:org-guard-alerts" }
}

override_resource {
  target          = aws_iam_role.guard_alerts_forwarder
  override_during = plan
  values          = { arn = "arn:aws:iam::111111111111:role/org-guard-alerts-forwarder" }
}

# Plan-known member account IDs (the security-tooling exemption is account-qualified).
override_module {
  target = module.account
  outputs = {
    account_id             = "222222222222"
    account_arn            = "arn:aws:organizations::111111111111:account/o-abc1234567/222222222222"
    cross_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
  }
}

run "recorders_off_by_default" {
  command = plan

  assert {
    condition     = length(module.org_config_recorders) == 0 && length(module.management_config_recorder) == 0
    error_message = "the recorder StackSet and the management recorder must be off by default"
  }

  assert {
    condition     = output.org_config_recorder_stack_set_name == null
    error_message = "no StackSet name is published while the recorders are off"
  }

  # Today's behaviour: the recorder actions stay in DenyWeakenSecurityServices
  # (pipeline + break-glass exempt), and no recorder statement exists.
  assert {
    condition = (
      length([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyConfigRecorderChanges"]) == 0 &&
      length(setsubtract(
        ["config:PutConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel"],
        one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyWeakenSecurityServices"]).Action
      )) == 0
    )
    error_message = "with enable_config_recorder_scp = false the recorder actions must stay in DenyWeakenSecurityServices"
  }
}

run "management_direct_recorder_when_enabled" {
  command = plan

  variables {
    enable_org_config_recorders = true
    aws_enabled_regions         = ["eu-west-2", "eu-west-1"]
    org_trail_home_region       = "eu-west-2"
  }

  assert {
    condition     = length(module.management_config_recorder) == 1 && toset(keys(module.management_config_recorder[0].recorder_names)) == toset(["eu-west-1", "eu-west-2"])
    error_message = "the management account must get a direct recorder in every enabled Region"
  }

  assert {
    condition     = module.management_config_recorder[0].aggregator_arn == null
    error_message = "the management recorder is recorder-only (the aggregator stays in security tooling)"
  }

  assert {
    condition     = module.management_config_recorder[0].config_role_arn == "arn:aws:iam::111111111111:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "the management recorder must use the management account's Config service-linked role"
  }

  assert {
    condition     = output.org_config_recorder_stack_set_name == "org-config-recorders"
    error_message = "the org recorder StackSet must be composed when enabled"
  }

  assert {
    condition = alltrue([
      for i in module.org_config_recorders[0].stack_set_instances :
      tolist(i.organizational_unit_ids) == tolist(["r-abcd"]) && i.account_filter_type == "DIFFERENCE" && tolist(i.accounts) == tolist(["222222222222"])
    ]) && length(module.org_config_recorders[0].stack_set_instances) == 2
    error_message = "the StackSet must target the org root minus the security-tooling account, in every enabled Region"
  }

  assert {
    condition     = module.org_config_recorders[0].failure_tolerance_percentage == 0
    error_message = "the routine failure tolerance is 0"
  }

  # Put* are upserts by name: the StackSet must not reuse the legacy config-org
  # names (the management recorder uses the config-org defaults).
  assert {
    condition = (
      module.org_config_recorders[0].recorder_name != module.management_config_recorder[0].recorder_names["eu-west-2"] &&
      module.org_config_recorders[0].recorder_name == "org-stackset-recorder" &&
      module.org_config_recorders[0].delivery_channel_name == "org-stackset-delivery"
    )
    error_message = "the StackSet recorder / channel names must differ from the config-org (legacy) names"
  }
}

run "recorders_need_home_region_in_enabled_regions" {
  command = plan

  variables {
    enable_org_config_recorders = true
    aws_enabled_regions         = ["eu-west-1"]
    org_trail_home_region       = "eu-west-2"
  }

  expect_failures = [var.enable_org_config_recorders]
}

run "recorder_scp_apply_role_name_is_configurable" {
  command = plan

  variables {
    enable_config_recorder_scp       = true
    security_tooling_apply_role_name = "automation/tfc-apply-security"
  }

  assert {
    condition = contains(
      one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyConfigRecorderChanges"]).Condition.ArnNotLike["aws:PrincipalArn"],
      "arn:aws:iam::222222222222:role/automation/tfc-apply-security"
    )
    error_message = "the security-tooling exemption must follow security_tooling_apply_role_name"
  }
}

run "migration_tolerance_passes_through" {
  command = plan

  variables {
    enable_org_config_recorders                       = true
    org_config_recorders_failure_tolerance_percentage = 100
  }

  assert {
    condition     = module.org_config_recorders[0].failure_tolerance_percentage == 100
    error_message = "the migration pass must reach the StackSet failure tolerance"
  }
}

run "recorder_scp_exempts_only_qualified_arns" {
  command = plan

  variables {
    enable_config_recorder_scp = true
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyConfigRecorderChanges"]).Condition.ArnNotLike["aws:PrincipalArn"]) ==
      toset(["arn:aws:iam::*:role/stacksets-exec-*", "arn:aws:iam::*:role/break-glass", "arn:aws:iam::222222222222:role/tfc-apply"])
    )
    error_message = "the recorder SCP must exempt exactly stacksets-exec-*, break-glass and the security-tooling tfc-apply"
  }

  assert {
    condition     = keys(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyConfigRecorderChanges"]).Condition) == ["ArnNotLike"]
    error_message = "the recorder SCP must never exempt a whole account (no aws:PrincipalAccount condition)"
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyConfigRecorderChanges"]).Action) ==
      toset(["config:PutConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel", "config:PutDeliveryChannel"])
    )
    error_message = "DenyConfigRecorderChanges must hold the four recorder actions plus PutDeliveryChannel"
  }

  assert {
    condition = length(setintersection(
      ["config:PutConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel"],
      one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyWeakenSecurityServices"]).Action
    )) == 0
    error_message = "the recorder actions must move out of DenyWeakenSecurityServices"
  }

  assert {
    condition     = length(module.policies.policy_contents["scp-deny-tamper"]) <= 10240
    error_message = "deny-tamper SCP must stay within the 10,240-character SCP quota"
  }
}

# Routine applies keep working under the recorder SCP.
run "recorder_scp_keeps_routine_applies" {
  command = plan

  variables {
    enable_config_recorder_scp = true
  }

  # Security tooling's tfc-apply manages its own aggregator recorder.
  assert {
    condition = alltrue([
      for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement :
      contains(s.Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::222222222222:role/tfc-apply")
      if contains(flatten([s.Action]), "config:PutConfigurationRecorder")
    ])
    error_message = "the security-tooling tfc-apply must still be able to PutConfigurationRecorder"
  }

  # The workload tfc-apply still creates and replaces flow logs.
  assert {
    condition = (
      length([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if contains(flatten([s.Action]), "ec2:CreateFlowLogs")]) == 0 &&
      alltrue([
        for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement :
        contains(s.Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/tfc-apply")
        if contains(flatten([s.Action]), "ec2:DeleteFlowLogs")
      ])
    )
    error_message = "the workload tfc-apply must still be able to CreateFlowLogs and DeleteFlowLogs"
  }
}

run "recorders_need_a_security_tooling_account" {
  command = plan

  variables {
    enable_org_config_recorders = true
    accounts = {
      log_archive = { email = "aws+log-archive@acme.test", ou = "Security" }
    }
    tfc_workspace_bindings            = {}
    central_detection_account_keys    = []
    identity_center_admin_account_key = null
  }

  expect_failures = [var.enable_org_config_recorders]
}
