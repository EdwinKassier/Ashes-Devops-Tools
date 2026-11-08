# Plan-assertion tests for the aws-organization stage.
#
# Uses mock_provider so no AWS credentials are required. module.organization is
# overridden with known root/OU/organization IDs so that (a) the guardrail
# attachment for_each targets and the org-identity/account-id inputs to the
# policy module are known at plan, and (b) the assertions on plan-known output
# keys are non-vacuous.

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

run "composes_accounts_and_guardrails" {
  command = plan

  assert {
    condition     = contains(keys(output.account_ids), "security_tooling")
    error_message = "the security_tooling foundational account must be created"
  }

  assert {
    condition     = contains(keys(output.account_ids), "forensics")
    error_message = "the forensics foundational account must be created"
  }

  assert {
    condition     = length(keys(output.account_ids)) >= 6
    error_message = "at least the six foundational accounts must be created"
  }

  assert {
    condition     = contains(keys(output.policy_attachment_ids), "deny-tamper@root")
    error_message = "the deny-tamper guardrail must be attached to the root"
  }

  assert {
    condition     = length(output.policy_attachment_ids) >= 6
    error_message = "at least six guardrail attachments must be created"
  }

  # cost-governance is composed: budget for_each keys are plan-known.
  assert {
    condition     = contains(keys(output.cost_budget_ids), "org-monthly")
    error_message = "the cost-governance module must be composed with the default org-monthly budget"
  }
}

# TFC OIDC baseline: member-account plan/apply roles are published per bound
# account, and the StackSet targets the OUs of those accounts.
run "tfc_oidc_baseline_is_composed" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["security_tooling", "log_archive", "forensics", "network", "shared_services", "backup"] :
      contains(keys(output.tfc_plan_role_arns), k) && contains(keys(output.tfc_apply_role_arns), k)
    ])
    error_message = "every default-bound foundational account must publish tfc_plan_role_arns / tfc_apply_role_arns"
  }

  assert {
    # Account IDs are computed at plan (new accounts), so assert the role names
    # the ARNs are built from; the module's own tests assert the full ARN shape.
    condition     = module.tfc_oidc_baseline[0].plan_role_name == "tfc-plan" && module.tfc_oidc_baseline[0].apply_role_name == "tfc-apply"
    error_message = "role ARNs must point at the tfc-plan / tfc-apply roles"
  }

  assert {
    condition     = keys(module.tfc_oidc_baseline[0].stack_set_instance_ids) == ["Infrastructure", "Security"]
    error_message = "the StackSet must target exactly the OUs of the bound accounts (Security + Infrastructure by default)"
  }

  assert {
    condition     = tolist(output.tfc_workspace_bindings["shared_services"]) == tolist(["aws-identity", "aws-shared-services"])
    error_message = "shared_services must be bound to the aws-identity and aws-shared-services workspaces"
  }
}

run "member_break_glass_role_deployed_to_every_member_account" {
  # N1(b): the SCP-exempt break-glass name is occupied in every member account.
  command = plan

  assert {
    condition     = output.member_break_glass_stack_set_name == "member-break-glass"
    error_message = "the member break-glass StackSet must be composed by default"
  }

  assert {
    condition = (
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.RoleName == "break-glass" &&
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Principal.AWS == [var.break_glass_role_arn] &&
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true"
    )
    error_message = "the member role must carry the SCP break-glass name and trust the management break-glass role with MFA"
  }

  assert {
    condition     = module.tfc_oidc_baseline[0].member_break_glass_stack_set_name != null
    error_message = "the member break-glass StackSet must exist when the baseline is enabled"
  }
}

run "member_break_glass_role_follows_explicit_scp_name" {
  command = plan

  variables {
    break_glass_role_names                    = ["emergency/break-glass-admin"]
    member_break_glass_trusted_principal_arns = ["arn:aws:iam::111111111111:user/bg-responder"]
  }

  assert {
    condition = (
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.RoleName == "break-glass-admin" &&
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.Path == "/emergency/" &&
      jsondecode(module.tfc_oidc_baseline[0].member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Principal.AWS == ["arn:aws:iam::111111111111:user/bg-responder"]
    )
    error_message = "the member role must use the explicit SCP break-glass name (path split) and the explicit trusted principals"
  }
}

run "member_break_glass_role_can_be_disabled" {
  command = plan

  variables {
    enable_member_break_glass_role = false
  }

  assert {
    condition     = output.member_break_glass_stack_set_name == null
    error_message = "enable_member_break_glass_role = false must not deploy the member break-glass StackSet"
  }
}

run "tfc_oidc_baseline_can_be_disabled" {
  command = plan

  variables {
    enable_tfc_oidc_baseline = false
    tfc_organization         = null
  }

  assert {
    condition     = length(module.tfc_oidc_baseline) == 0 && output.tfc_plan_role_arns == {} && output.tfc_oidc_stack_set_name == null
    error_message = "enable_tfc_oidc_baseline = false must compose no baseline and publish empty role maps"
  }
}

# The RCP pins TFC web-identity federation to this TFC organization by default.
run "rcp_pins_tfc_federation_by_default" {
  command = plan

  variables {
    github_federation_owners = ["acme"]
  }

  assert {
    condition = (
      one([for s in jsondecode(module.policies.policy_contents["rcp-data-perimeter"]).Statement : s if s.Sid == "PinTfcFederationToOrg"]).Condition.StringNotLike["app.terraform.io:sub"] == "organization:acme:*" &&
      length([for s in jsondecode(module.policies.policy_contents["rcp-data-perimeter"]).Statement : s if s.Sid == "PinGithubFederationToOwners"]) == 1
    )
    error_message = "the stage must pin TFC federation to tfc_organization and GitHub federation to github_federation_owners."
  }
}

run "rcp_tfc_pin_opt_out" {
  command = plan

  variables {
    pin_tfc_federation_to_org = false
    github_federation_owners  = []
    enable_tfc_oidc_baseline  = false
  }

  assert {
    condition     = length([for s in jsondecode(module.policies.policy_contents["rcp-data-perimeter"]).Statement : s if startswith(s.Sid, "Pin")]) == 0
    error_message = "pin_tfc_federation_to_org = false (and no GitHub owners) must render no pin statements."
  }
}

# The stage attaches the EC2 baseline and AI opt-out at the root, and does not
# create the unattached duplicate backup policy (the backup stage owns it).
run "root_baseline_policies_attached" {
  command = plan

  assert {
    condition = (
      module.policies.attachment_ids != null &&
      contains(keys(local.effective_attachments), "declarative-baseline@root") &&
      contains(keys(local.effective_attachments), "aiservices-opt-out@root") &&
      !contains(keys(module.policies.policy_contents), "backup-policy")
    )
    error_message = "the root must get the EC2 baseline and AI opt-out; backup-policy is disabled by default."
  }
}

# aws-organization deploys the member Backup service role to the Workloads OU.
run "backup_service_role_stack_set" {
  command = plan

  assert {
    condition = (
      aws_cloudformation_stack_set.backup_service_role[0].permission_model == "SERVICE_MANAGED" &&
      tolist(aws_cloudformation_stack_set_instance.backup_service_role[0].deployment_targets[0].organizational_unit_ids) == tolist(["ou-abcd-workload0"]) &&
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.BackupServiceRole.Properties.RoleName == "aws-backup-org-role"
    )
    error_message = "the Backup service role must be deployed by a service-managed StackSet to the Workloads OU."
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVault.Type == "AWS::Backup::BackupVault" &&
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVault.Properties.BackupVaultName == "org-backup-vault" &&
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVault.DeletionPolicy == "Retain"
    )
    error_message = "every Workloads-OU account must get the org-backup-vault the BACKUP_POLICY writes to, retained on stack deletion."
  }
}

run "member_backup_vault_can_be_disabled" {
  command = plan

  variables {
    create_member_backup_vault = false
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources), "MemberBackupVault")
    error_message = "create_member_backup_vault = false must leave only the service role in the StackSet."
  }
}

run "unpinned_github_with_baseline_warns" {
  command = plan

  variables {
    github_federation_owners = []
  }

  expect_failures = [check.github_federation_pinned]
}

# aws-organization owns the trail delivery role and Identity Center delegation,
# so the least-privilege aws-security role needs neither IAM writes nor sso.
run "organization_owns_trail_role_and_identity_center_delegation" {
  command = plan

  assert {
    condition = (
      aws_iam_role.org_trail_cloudwatch[0].name == "org-trail-cloudwatch-delivery" &&
      jsondecode(aws_iam_role.org_trail_cloudwatch[0].assume_role_policy).Statement[0].Principal.Service == "cloudtrail.amazonaws.com" &&
      aws_organizations_delegated_administrator.identity_center[0].service_principal == "sso.amazonaws.com"
    )
    error_message = "aws-organization must create the trail delivery role and register the Identity Center delegated admin."
  }
}

run "github_provider_only_when_pinned" {
  command = plan

  variables {
    github_federation_owners = []
  }

  # The baseline's own suite (github_provider_opt_out) proves that
  # create_github_oidc_provider = false omits the provider; the template body
  # is unknown at plan here (it embeds computed account IDs).
  expect_failures = [check.github_federation_pinned]
}

# Guard alerts: owned by aws-organization (out of the aws-security role's
# reach), in us-east-1 where Organizations events arrive.
run "guard_topic_in_us_east_1_with_events_kms_grant" {
  command = plan

  variables {
    guard_alert_emails = ["secops@example.com"]
  }

  assert {
    condition = (
      aws_sns_topic.guard_alerts.name == "org-guard-alerts" &&
      aws_sns_topic.guard_alerts.region == "us-east-1" &&
      aws_kms_key.guard_alerts.region == "us-east-1" &&
      aws_kms_key.guard_alerts.enable_key_rotation
    )
    error_message = "org-guard-alerts and its rotating CMK must live in us-east-1."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.guard_alerts.policy).Statement :
      s.Effect == "Allow" && try(s.Principal.Service, "") == "events.amazonaws.com" &&
      toset(flatten([s.Action])) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
    ])
    error_message = "The guard-alerts CMK must let events.amazonaws.com call kms:GenerateDataKey* and kms:Decrypt."
  }

  # The topic accepts publishes only from the guard rule.
  assert {
    condition = anytrue([
      for s in jsondecode(aws_sns_topic_policy.guard_alerts.policy).Statement :
      s.Effect == "Allow" && try(s.Principal.Service, "") == "events.amazonaws.com" && s.Action == "sns:Publish" &&
      s.Condition.ArnEquals["aws:SourceArn"] == "arn:aws:events:us-east-1:111111111111:rule/org-guard-alerts"
    ])
    error_message = "Only the us-east-1 org-guard-alerts rule may publish to the topic."
  }

  assert {
    condition = (
      toset([for s in aws_sns_topic_subscription.guard_alerts : s.endpoint]) == toset(["secops@example.com"]) &&
      alltrue([for s in aws_sns_topic_subscription.guard_alerts : s.protocol == "email" && s.region == "us-east-1"])
    )
    error_message = "guard_alert_emails must be subscribed (email) to the topic."
  }

  # The us-east-1 rule matches the org-detection teardown and trail tampering
  # calls, and targets the topic.
  assert {
    condition = (
      aws_cloudwatch_event_rule.guard_alerts.region == "us-east-1" &&
      aws_cloudwatch_event_rule.guard_alerts.name == "org-guard-alerts" &&
      aws_cloudwatch_event_target.guard_alerts.region == "us-east-1" &&
      aws_cloudwatch_event_target.guard_alerts.rule == "org-guard-alerts" &&
      jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern)["detail-type"] == ["AWS API Call via CloudTrail"] &&
      toset(flatten([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] : b.eventName])) == toset([
        "DisableAWSServiceAccess", "DeregisterDelegatedAdministrator",
        "PutEventSelectors", "PutInsightSelectors", "RemoveTags",
        "DisableOrganizationAdminAccount", "DisableDelegatedAdminAccount", "DisassociateAdminAccount",
        "PutMetricAlarm", "DeleteAlarms", "DisableAlarmActions",
        "DeleteTopic", "SetTopicAttributes", "Unsubscribe",
        "PutMetricFilter", "DeleteMetricFilter", "DeleteLogStream",
      ]) &&
      toset(flatten([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] : b.eventSource])) == toset([
        "organizations.amazonaws.com", "cloudtrail.amazonaws.com", "guardduty.amazonaws.com",
        "securityhub.amazonaws.com", "macie2.amazonaws.com", "inspector2.amazonaws.com",
        "detective.amazonaws.com", "fms.amazonaws.com",
        "monitoring.amazonaws.com", "sns.amazonaws.com", "logs.amazonaws.com",
      ])
    )
    error_message = "The us-east-1 org-guard-alerts rule must match the detection-teardown and trail-tampering CloudTrail calls and target the topic."
  }

  # Trail calls are filtered to THE org trail (name or ARN).
  assert {
    condition = anytrue([
      for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      contains(b.eventName, "PutEventSelectors") && contains(b.requestParameters.trailName, "org-trail")
    ])
    error_message = "Selector calls must be matched on the org trail."
  }

  # Silencing the CIS alerting (detect-only paths left open on the role).
  assert {
    condition = (
      anytrue([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      contains(b.eventName, "PutMetricAlarm") && try(b.requestParameters.actionsEnabled == [false], false) && try(b.requestParameters.alarmName[0].wildcard == "org-trail-*", false)]) &&
      anytrue([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      contains(b.eventName, "PutMetricAlarm") && try(b.requestParameters.alarmActions[0].exists == false, false)]) &&
      anytrue([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      contains(b.eventName, "DeleteTopic") && try(b.requestParameters.topicArn[0].wildcard == "*:org-trail-cis-alarms", false)]) &&
      anytrue([for b in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      contains(b.eventName, "PutMetricFilter") && try(b.requestParameters.logGroupName == ["/aws/cloudtrail/org-trail"], false)])
    )
    error_message = "The guard rule must match CIS-alarm silencing, CIS topic tampering and trail metric-filter overwrites."
  }

  # EventBridge caps an event pattern at 4,096 characters... keep a margin.
  assert {
    condition     = length(aws_cloudwatch_event_rule.guard_alerts.event_pattern) <= 4096
    error_message = "The guard event pattern must stay within the EventBridge event-pattern size."
  }
}

run "other_regions_forward_to_us_east_1_bus_with_role" {
  command = plan

  variables {
    aws_enabled_regions = ["eu-west-2", "us-east-1", "eu-west-1"]
  }

  assert {
    condition = (
      toset(keys(aws_cloudwatch_event_rule.guard_alerts_forward)) == toset(["eu-west-2", "eu-west-1"]) &&
      alltrue([for r, rule in aws_cloudwatch_event_rule.guard_alerts_forward : rule.region == r && rule.event_pattern == aws_cloudwatch_event_rule.guard_alerts.event_pattern])
    )
    error_message = "Every enabled region except us-east-1 must get a forwarding rule with the same pattern."
  }

  assert {
    condition = alltrue([
      for r, t in aws_cloudwatch_event_target.guard_alerts_forward :
      t.region == r && t.arn == "arn:aws:events:us-east-1:111111111111:event-bus/default" && t.role_arn == aws_iam_role.guard_alerts_forwarder.arn
    ])
    error_message = "Forwarding rules must target the us-east-1 default bus with the forwarder role."
  }

  assert {
    condition = (
      aws_iam_role.guard_alerts_forwarder.name == "org-guard-alerts-forwarder" &&
      jsondecode(aws_iam_role.guard_alerts_forwarder.assume_role_policy).Statement[0].Principal.Service == "events.amazonaws.com" &&
      jsondecode(aws_iam_role_policy.guard_alerts_forwarder.policy).Statement[0].Action == "events:PutEvents" &&
      jsondecode(aws_iam_role_policy.guard_alerts_forwarder.policy).Statement[0].Resource == "arn:aws:events:us-east-1:111111111111:event-bus/default"
    )
    error_message = "The forwarder role must be assumable by EventBridge and only PutEvents to the us-east-1 default bus."
  }
}

# Single-region us-east-1 landing zone: no forwarding rules; no emails = no subscriptions.
run "guard_alerts_us_east_1_only_minimum_config" {
  command = plan

  variables {
    aws_enabled_regions   = ["us-east-1"]
    org_trail_home_region = "us-east-1"
    guard_alert_emails    = []
  }

  # No emails: only the warning check fires.
  expect_failures = [check.guard_alert_emails_set]

  assert {
    condition     = length(aws_cloudwatch_event_rule.guard_alerts_forward) == 0 && length(aws_sns_topic_subscription.guard_alerts) == 0
    error_message = "us-east-1 alone needs no forwarding rule, and no emails means no subscriptions."
  }
}

# The trail's home region always forwards, even when not an enabled region.
run "trail_home_region_always_forwards" {
  command = plan

  variables {
    aws_enabled_regions   = ["eu-west-1"]
    org_trail_home_region = "eu-central-1"
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_event_rule.guard_alerts_forward)) == toset(["eu-west-1", "eu-central-1"])
    error_message = "The org trail home region must get a forwarding rule."
  }
}

# The tfc-management-roles trail scope follows org_trail_name.
run "trail_name_reaches_management_roles" {
  command = plan

  variables {
    org_trail_name = "acme-trail"
  }

  # Plan-known account IDs so the management-role policy is plan-known.
  override_module {
    target = module.account
    outputs = {
      account_id             = "222222222222"
      account_arn            = "arn:aws:organizations::111111111111:account/o-abc1234567/222222222222"
      cross_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
    }
  }

  assert {
    condition = (
      one([for s in jsondecode(module.tfc_management_roles[0].apply_policies["aws-security"]).Statement : s if s.Sid == "OrganizationTrailOnly"]).Resource == ["arn:aws:cloudtrail:*:111111111111:trail/acme-trail"] &&
      one([for s in jsondecode(module.tfc_management_roles[0].apply_policies["aws-security"]).Statement : s if s.Sid == "PassTrailDeliveryRoleToCloudTrail"]).Resource == ["arn:aws:iam::111111111111:role/acme-trail-cloudwatch-delivery"] &&
      strcontains(aws_cloudwatch_event_rule.guard_alerts.event_pattern, "acme-trail-cis-alarms")
    )
    error_message = "org_trail_name must drive the management role's trail scope, the delivery-role PassRole and the guard pattern."
  }
}

run "no_guard_alert_emails_warns" {
  command = plan

  variables {
    guard_alert_emails = []
  }

  expect_failures = [check.guard_alert_emails_set]
}

run "teardown_gate_passes_through" {
  command = plan

  variables {
    enable_security_service_teardown = true
  }

  assert {
    condition     = length(module.tfc_management_roles[0].security_teardown_policy) > 0
    error_message = "enable_security_service_teardown must reach tfc-management-roles."
  }
}

run "suspended_and_sandbox_policies_attached" {
  command = plan

  assert {
    condition = (
      local.effective_attachments["suspended-deny-all@suspended"].target_id == "ou-abcd-suspend00" &&
      local.effective_attachments["suspended-deny-all@suspended"].policy_key == "scp-suspended-deny-all" &&
      local.effective_attachments["sandbox-guard@sandbox"].target_id == "ou-abcd-sandbox00" &&
      local.effective_attachments["sandbox-guard@sandbox"].policy_key == "scp-sandbox-guard"
    )
    error_message = "Suspended must get the deny-all SCP and Sandbox the guard SCP"
  }
}

run "per_target_scp_count_le_10" {
  command = plan

  # FullAWSAccess is attached by AWS to every target and counts toward the
  # 10-SCP quota, so at most 9 managed SCPs per target.
  assert {
    condition = alltrue([
      for t in distinct([for k, a in local.effective_attachments : a.target_id]) :
      length([for k, a in local.effective_attachments : k if a.target_id == t && startswith(a.policy_key, "scp-")]) <= 9
    ])
    error_message = "a target may carry at most 10 SCPs including FullAWSAccess"
  }
}

run "missing_sandbox_ou_skips_guard_attachment" {
  command = plan

  override_module {
    target = module.organization
    outputs = {
      organization_id       = "o-abc1234567"
      organization_arn      = "arn:aws:organizations::111111111111:organization/o-abc1234567"
      roots_id              = "r-abcd"
      management_account_id = "111111111111"
      ou_ids = {
        "Security"       = "ou-abcd-security0"
        "Infrastructure" = "ou-abcd-infra0000"
        "Workloads"      = "ou-abcd-workload0"
      }
    }
  }

  assert {
    condition     = !contains(keys(local.effective_attachments), "sandbox-guard@sandbox") && !contains(keys(local.effective_attachments), "suspended-deny-all@suspended")
    error_message = "attachments for absent OUs must be skipped, not fail"
  }
}

# CloudTrail delegated admin: security tooling is registered through CloudTrail
# (not the generic Organizations resource), and the aws-security management
# role loses every trail write.
run "cloudtrail_delegated_admin_registered_through_cloudtrail" {
  command = plan

  variables {
    enable_cloudtrail_delegated_admin = true
  }

  override_module {
    target = module.account
    outputs = {
      account_id             = "222222222222"
      account_arn            = "arn:aws:organizations::111111111111:account/o-abc1234567/222222222222"
      cross_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
    }
  }

  assert {
    condition = (
      aws_cloudtrail_organization_delegated_admin_account.this[0].account_id == "222222222222" &&
      output.cloudtrail_delegated_admin_account_id == "222222222222"
    )
    error_message = "enable_cloudtrail_delegated_admin must register security tooling through aws_cloudtrail_organization_delegated_admin_account."
  }

  assert {
    condition = (
      !anytrue([for s in jsondecode(module.tfc_management_roles[0].apply_policies["aws-security"]).Statement : s.Effect == "Allow" && anytrue([for a in flatten([s.Action]) : startswith(a, "cloudtrail:") || a == "iam:PassRole"])])
    )
    error_message = "With the CloudTrail delegated admin, the aws-security management role must allow no cloudtrail action and no PassRole."
  }
}

run "cloudtrail_delegated_admin_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail_organization_delegated_admin_account.this) == 0 && output.cloudtrail_delegated_admin_account_id == null
    error_message = "The CloudTrail delegated admin must be opt-in."
  }
}

# No new SCP statement: once the trail is managed from security tooling, the
# existing deny-tamper statements cover it. Stop/delete is break-glass only;
# selector and trail updates are allowed only to the pipeline (privileged) and,
# with central detection, only from the security accounts.
run "scp_denies_trail_tamper_except_exempt" {
  command = plan

  variables {
    enable_cloudtrail_delegated_admin = true
  }

  override_module {
    target = module.account
    outputs = {
      account_id             = "222222222222"
      account_arn            = "arn:aws:organizations::111111111111:account/o-abc1234567/222222222222"
      cross_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
    }
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyDisableSecurityServices"]).Condition.ArnNotLike["aws:PrincipalArn"]) == toset(["arn:aws:iam::*:role/break-glass"]) &&
      length(setsubtract(["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"], one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyDisableSecurityServices"]).Action)) == 0
    )
    error_message = "Stopping or deleting any trail must be denied to everyone but break-glass."
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyWeakenSecurityServices"]).Condition.ArnNotLike["aws:PrincipalArn"]) == toset([
        "arn:aws:iam::*:role/tfc-apply", "arn:aws:iam::*:role/OrganizationAccountAccessRole", "arn:aws:iam::*:role/stacksets-exec-*", "arn:aws:iam::*:role/break-glass",
      ]) &&
      length(setsubtract(["cloudtrail:PutEventSelectors", "cloudtrail:PutInsightSelectors", "cloudtrail:UpdateTrail"], one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyWeakenSecurityServices"]).Action)) == 0
    )
    error_message = "Weakening a trail must be denied to everyone but the pipeline roles and break-glass."
  }

  assert {
    condition = (
      # Every account resolves to 222222222222 under the override (security_tooling, log_archive).
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Condition.StringNotEquals["aws:PrincipalAccount"]) == toset(["222222222222"]) &&
      toset(one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Condition.ArnNotLike["aws:PrincipalArn"]) == toset(["arn:aws:iam::*:role/break-glass"]) &&
      length(setsubtract(["cloudtrail:PutEventSelectors", "cloudtrail:PutInsightSelectors", "cloudtrail:UpdateTrail"], one([for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Action)) == 0
    )
    error_message = "Trail changes from outside the security accounts must be denied to everyone but break-glass."
  }

  # Only those three statements carry cloudtrail actions: no new statement.
  assert {
    condition = toset([
      for s in jsondecode(module.policies.policy_contents["scp-deny-tamper"]).Statement : s.Sid
      if anytrue([for a in flatten([s.Action]) : startswith(a, "cloudtrail:")])
    ]) == toset(["DenyDisableSecurityServices", "DenyWeakenSecurityServices", "DenyCentralDetectionOutsideSecurityAccounts"])
    error_message = "The CloudTrail delegated admin must add no SCP statement: the three existing ones cover trail tampering."
  }
}

# With the delegated admin, any trail change made from the management account
# (phase-0 or break-glass: SCPs never apply there) alerts, whatever the trail
# name; the default pattern is unchanged.
run "guard_alerts_any_management_trail_change_with_delegated_admin" {
  command = plan

  variables {
    enable_cloudtrail_delegated_admin = true
  }

  override_module {
    target = module.account
    outputs = {
      account_id             = "222222222222"
      account_arn            = "arn:aws:organizations::111111111111:account/o-abc1234567/222222222222"
      cross_account_role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
    }
  }

  assert {
    condition = anytrue([
      for c in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      c.eventSource == ["cloudtrail.amazonaws.com"] && !can(c.requestParameters) && length(setsubtract(["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"], c.eventName)) == 0
    ])
    error_message = "With the delegated admin the guard rule must alert on any management-account trail change, on any trail."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guard_alerts.event_pattern) <= 4096
    error_message = "The extended guard event pattern must stay within the EventBridge event-pattern size."
  }
}

run "guard_alerts_trail_scoped_by_default" {
  command = plan

  assert {
    condition = !anytrue([
      for c in jsondecode(aws_cloudwatch_event_rule.guard_alerts.event_pattern).detail["$or"] :
      c.eventSource == ["cloudtrail.amazonaws.com"] && !can(c.requestParameters)
    ])
    error_message = "By default every guard-rule CloudTrail clause stays scoped to the org trail."
  }
}
