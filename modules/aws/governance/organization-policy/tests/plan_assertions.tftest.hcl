# Resource-assertion tests for the aws/organization-policy module.
#
# The provider does not parse aws_organizations_policy.content at plan, so these
# assertions inspect the rendered template strings directly. Where practical we
# jsondecode() the rendered content to prove it is valid JSON with the expected
# keys (the raw files carry ${...} placeholders and cannot be parsed standalone).

mock_provider "aws" {}

variables {
  org_id                  = "o-abc1234567"
  allowed_regions         = ["eu-west-2", "eu-west-1"]
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
}

run "guardrail_policies_render_correctly" {
  command = plan

  assert {
    condition     = can(regex("organizations:LeaveOrganization", aws_organizations_policy.policy["scp-deny-tamper"].content))
    error_message = "deny-tamper SCP must deny organizations:LeaveOrganization"
  }

  assert {
    condition     = can(regex("aws:RequestedRegion", aws_organizations_policy.policy["scp-region-restriction"].content))
    error_message = "region-restriction SCP must condition on aws:RequestedRegion"
  }

  assert {
    condition     = can(regex("arn:aws:iam::[*]:root", aws_organizations_policy.policy["scp-baseline"].content))
    error_message = "baseline SCP must deny root-user actions in member accounts"
  }

  assert {
    condition     = aws_organizations_policy.policy["rcp-data-perimeter"].type == "RESOURCE_CONTROL_POLICY"
    error_message = "rcp-data-perimeter must be a RESOURCE_CONTROL_POLICY"
  }

  assert {
    condition     = length(regexall("aws:SourceOrgID", aws_organizations_policy.policy["rcp-data-perimeter"].content)) > 0
    error_message = "RCP must scope the AWS-service exemption with aws:SourceOrgID"
  }

  assert {
    condition     = can(regex("aws:SecureTransport", aws_organizations_policy.policy["rcp-data-perimeter"].content))
    error_message = "RCP must require secure transport"
  }

  assert {
    condition     = can(regex("@@assign", aws_organizations_policy.policy["declarative-ec2"].content))
    error_message = "declarative content must use @@assign syntax"
  }

  # Robust validity check: every rendered content must be valid JSON.
  assert {
    condition     = jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Version == "2012-10-17"
    error_message = "deny-tamper SCP must render to valid IAM policy JSON"
  }

  # The Terraform run role must NOT be exempt from the tamper-deny statements,
  # so a pipeline compromise cannot disable security services or leave the org.
  assert {
    condition = alltrue([
      for sid in ["DenyLeaveOrganization", "DenyDisableSecurityServices"] :
      !contains(
        one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == sid]).Condition.ArnNotLike["aws:PrincipalArn"],
        var.terraform_run_role_arn
      )
    ])
    error_message = "run role must NOT be exempt from DenyLeaveOrganization/DenyDisableSecurityServices"
  }

  # Break-glass remains the SOLE exemption for the destructive tamper-deny
  # statements, keyed on a member-account role-name pattern (SCPs never apply to
  # the management account, so a management-account ARN would never match).
  assert {
    condition = alltrue([
      for sid in ["DenyLeaveOrganization", "DenyDisableSecurityServices", "DenyProtectedKeyDestruction", "DenyProtectedKeyUntag"] :
      one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == sid]).Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    ])
    error_message = "break-glass (arn:aws:iam::*:role/break-glass) must be the sole exemption from the destructive tamper-deny statements"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement[0].Principal == "*"
    error_message = "RCP statements must set Principal to *"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["declarative-ec2"].content).ec2_attributes.instance_metadata_defaults.http_tokens["@@assign"] == "required"
    error_message = "declarative EC2 policy must enforce IMDSv2 (http_tokens required)"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.CostCenter.tag_key["@@assign"] == "CostCenter"
    error_message = "tag policy must enforce the CostCenter tag key"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["backup-policy"].content).plans.default.regions["@@assign"][0] == "eu-west-2"
    error_message = "backup policy must target the default region"
  }

  assert {
    condition     = length(keys(aws_organizations_policy.policy)) == 9
    error_message = "the built-in guardrail set must produce all nine policies"
  }
}

run "deny_tamper_scp_hardened" {
  command = plan

  # Carve-outs must match MEMBER-account sessions: no account-qualified ARN
  # (management-account ARNs are inert in an SCP) may appear anywhere.
  assert {
    condition     = !can(regex("arn:aws:iam::[0-9]{12}:", aws_organizations_policy.policy["scp-deny-tamper"].content))
    error_message = "deny-tamper SCP must not reference account-qualified (management-account) role ARNs"
  }

  # Previously-missing tamper actions are now denied.
  assert {
    condition = length(setsubtract(
      [
        "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:PutEventSelectors", "cloudtrail:UpdateTrail", "cloudtrail:PutInsightSelectors",
        "guardduty:DeleteDetector", "guardduty:CreateFilter", "guardduty:UpdateFilter", "guardduty:UpdateDetector", "guardduty:DeleteMembers", "guardduty:DisassociateFromAdministratorAccount",
        "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:PutConfigurationRecorder", "config:DeleteDeliveryChannel",
        "securityhub:BatchDisableStandards", "securityhub:DisableSecurityHub", "access-analyzer:DeleteAnalyzer", "ec2:DeleteFlowLogs",
        "macie2:DisableMacie", "inspector2:Disable", "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
      ],
      flatten([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s.Action])
    )) == 0
    error_message = "deny-tamper SCP must deny every audited tamper action"
  }

  # Pipeline roles are exempt from reconfiguration (workload Config recorders are
  # Terraform-managed in member accounts) but NOT from the destructive statements.
  assert {
    condition = alltrue([
      for p in ["arn:aws:iam::*:role/tfc-apply", "arn:aws:iam::*:role/OrganizationAccountAccessRole", "arn:aws:iam::*:role/break-glass"] :
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyWeakenSecurityServices"]).Condition.ArnNotLike["aws:PrincipalArn"], p)
    ])
    error_message = "pipeline roles and break-glass must be exempt from DenyWeakenSecurityServices"
  }

  # Pipeline roles, OAAR and break-glass are protected from IAM modification
  # (across the two role-tamper tiers).
  assert {
    condition = alltrue([
      for p in ["arn:aws:iam::*:role/tfc-apply", "arn:aws:iam::*:role/tfc-plan", "arn:aws:iam::*:role/OrganizationAccountAccessRole", "arn:aws:iam::*:role/stacksets-exec-*", "arn:aws:iam::*:role/break-glass"] :
      contains(flatten([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s.Resource if contains(["DenyPrivilegedRoleTampering", "DenyStackSetRoleTampering"], s.Sid)]), p)
    ]) && alltrue([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : contains(s.Action, "iam:UpdateAssumeRolePolicy") && contains(s.Action, "iam:CreateRole") if contains(["DenyPrivilegedRoleTampering", "DenyStackSetRoleTampering"], s.Sid)])
    error_message = "the role-tamper statements must protect tfc-plan/tfc-apply, OAAR, stacksets-exec-* and break-glass from create and trust-policy changes"
  }

  # Protected KMS keys: destruction is keyed on the protection resource tag.
  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyProtectedKeyDestruction"]).Condition.StringEquals["aws:ResourceTag/protected"] == "true"
    error_message = "DenyProtectedKeyDestruction must be scoped to keys tagged protected=true"
  }

  # SCP size quota (5,120 characters).
  assert {
    condition     = length(aws_organizations_policy.policy["scp-deny-tamper"].content) < 5120
    error_message = "deny-tamper SCP must stay under the 5,120-character SCP size quota"
  }
}

run "privileged_role_tamper_never_exempts_the_pipeline" {
  # A compromised member tfc-apply must not be able to CreateRole with the
  # break-glass name (inheriting every break-glass SCP exemption) nor rewrite
  # OrganizationAccountAccessRole's trust and assume it.
  command = plan

  # OAAR + the StackSet execution role: break-glass is the SOLE exemption.
  assert {
    condition = (
      toset(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]).Resource) == toset(["arn:aws:iam::*:role/OrganizationAccountAccessRole", "arn:aws:iam::*:role/stacksets-exec-*"]) &&
      one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]).Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    )
    error_message = "DenyPrivilegedRoleTampering must protect OAAR + stacksets-exec-* and exempt break-glass only"
  }

  # StackSet-managed roles (tfc-plan, tfc-apply, member break-glass): exempt
  # break-glass and the StackSet execution role only.
  assert {
    condition = (
      toset(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyStackSetRoleTampering"]).Resource) == toset(["arn:aws:iam::*:role/tfc-plan", "arn:aws:iam::*:role/tfc-apply", "arn:aws:iam::*:role/break-glass"]) &&
      toset(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyStackSetRoleTampering"]).Condition.ArnNotLike["aws:PrincipalArn"]) == toset(["arn:aws:iam::*:role/break-glass", "arn:aws:iam::*:role/stacksets-exec-*"])
    )
    error_message = "DenyStackSetRoleTampering must protect tfc-plan/tfc-apply/break-glass and exempt only break-glass + stacksets-exec-*"
  }

  # No role-tamper statement exempts tfc-apply or OAAR.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement :
      !contains(s.Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/tfc-apply") && !contains(s.Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/OrganizationAccountAccessRole")
      if contains(["DenyPrivilegedRoleTampering", "DenyStackSetRoleTampering"], s.Sid)
    ])
    error_message = "the pipeline roles must never be exempt from the privileged-role tamper denies"
  }

  # The OAAR tier never covers the StackSet-managed names (so stacksets-exec-*
  # can still maintain them) and the StackSet tier never covers OAAR.
  assert {
    condition     = !contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyStackSetRoleTampering"]).Resource, "arn:aws:iam::*:role/OrganizationAccountAccessRole")
    error_message = "the StackSet execution-role exemption must not extend to OrganizationAccountAccessRole"
  }

  assert {
    condition     = length(aws_organizations_policy.policy["scp-deny-tamper"].content) < 5120
    error_message = "deny-tamper SCP must stay under the 5,120-character SCP size quota"
  }
}

run "privileged_role_tier_omitted_when_every_pipeline_role_is_stackset_managed" {
  command = plan

  variables {
    pipeline_role_names           = ["tfc-apply"]
    stackset_execution_role_names = ["tfc-apply"]
  }

  assert {
    condition     = length([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]) == 0
    error_message = "an empty admin-role tier must be omitted (an empty Resource list is invalid policy)"
  }
}

run "protected_key_policy_change_is_break_glass_only" {
  command = plan

  # A pipeline role must not be able to rewrite a protected key policy (and
  # thereby grant itself kms:Decrypt) — break-glass is the sole exemption.
  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyProtectedKeyPolicyChange"]).Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    error_message = "DenyProtectedKeyPolicyChange must exempt break-glass only (no pipeline roles)"
  }
}

run "baseline_scp_identity_and_perimeter_guards" {
  command = plan

  # No IAM users / long-lived credentials org-wide except break-glass.
  assert {
    condition = (
      toset(one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyIamUserCredentials"]).Action) == toset(["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]) &&
      one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyIamUserCredentials"]).Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    )
    error_message = "DenyIamUserCredentials must deny CreateUser/CreateAccessKey/CreateLoginProfile for everyone but break-glass"
  }

  # Dp:* data-perimeter exemption tags can only be set/removed by break-glass,
  # on every tag-capable path (create-time tags and Tag/Untag) of each RCP service.
  assert {
    condition = (
      one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Condition["ForAnyValue:StringLike"]["aws:TagKeys"] == "dp:*" &&
      one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"] &&
      length(setsubtract(
        ["iam:CreateRole", "iam:TagRole", "iam:UntagRole", "s3:CreateBucket", "s3:PutBucketTagging", "s3:TagResource", "s3:UntagResource", "kms:CreateKey", "kms:TagResource", "kms:UntagResource", "sqs:CreateQueue", "sqs:TagQueue", "sqs:UntagQueue", "secretsmanager:CreateSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource"],
        one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Action
      )) == 0
    )
    error_message = "DenyDataPerimeterTagTampering must cover every dp:* tagging path for the RCP services, break-glass only"
  }

  # Every SCP stays under the 5,120-character quota.
  assert {
    condition     = alltrue([for k, p in aws_organizations_policy.policy : length(p.content) < 5120 if p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "every SCP must stay under the 5,120-character SCP size quota"
  }
}

run "deny_tamper_scp_size_with_custom_names" {
  # Realistic worst case: several path-prefixed pipeline roles plus a separate
  # member-account break-glass name must still fit the 5,120-character quota.
  command = plan

  variables {
    pipeline_role_names    = ["automation/tfc-plan", "automation/tfc-apply", "OrganizationAccountAccessRole", "stacksets-exec-*"]
    break_glass_role_names = ["emergency/break-glass-admin"]
  }

  assert {
    condition     = alltrue([for k, p in aws_organizations_policy.policy : length(p.content) < 5120 if p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "every SCP (incl. baseline with the identity/perimeter guards) must stay under the 5,120-character quota"
  }

  assert {
    condition     = length(aws_organizations_policy.policy["scp-deny-tamper"].content) < 5120
    error_message = "deny-tamper SCP must stay under the 5,120-character SCP size quota"
  }

  assert {
    condition     = contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyLeaveOrganization"]).Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/emergency/break-glass-admin")
    error_message = "explicit break_glass_role_names must override the name derived from break_glass_role_arn"
  }
}

run "rcp_data_perimeter_safe_for_federation_and_service_roles" {
  command = plan

  # EnforceOrgIdentities must NOT deny sts:* — that blocks OIDC/SAML
  # federation (TFC dynamic credentials) whose sessions carry no PrincipalOrgID.
  assert {
    condition     = !contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "EnforceOrgIdentities"]).Action, "sts:*")
    error_message = "EnforceOrgIdentities must not use sts:*"
  }

  assert {
    condition = alltrue([
      for sid in ["EnforceOrgIdentities", "ConfusedDeputyProtection"] : alltrue([
        for a in ["sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML", "sts:*"] :
        !contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == sid]).Action, a)
      ])
    ])
    error_message = "RCP perimeter statements must not cover AssumeRoleWithWebIdentity / AssumeRoleWithSAML"
  }

  assert {
    condition     = contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "EnforceOrgIdentities"]).Action, "sts:AssumeRole")
    error_message = "EnforceOrgIdentities must still cover sts:AssumeRole"
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "EnforceOrgIdentities"]).Condition.StringNotEqualsIfExists["aws:PrincipalOrgID"] == var.org_id
    error_message = "EnforceOrgIdentities must anchor on aws:PrincipalOrgID = org_id"
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "EnforceOrgIdentities"]).Condition.StringNotEqualsIfExists["aws:ResourceTag/dp:exclude:identity"] == "true"
    error_message = "EnforceOrgIdentities must honour the dp:exclude:identity resource-tag escape hatch"
  }

  # Null aws:SourceAccount guard: service-principal calls with no source context
  # (EC2 instance profiles, Lambda/ECS task roles) are not denied.
  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "ConfusedDeputyProtection"]).Condition.Null["aws:SourceAccount"] == "false"
    error_message = "ConfusedDeputyProtection must carry the Null aws:SourceAccount = false guard"
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "ConfusedDeputyProtection"]).Condition.StringNotEqualsIfExists["aws:SourceOrgID"] == var.org_id
    error_message = "ConfusedDeputyProtection must anchor on aws:SourceOrgID = org_id"
  }

  # No trusted accounts by default: the PrincipalAccount key is omitted entirely
  # (an empty condition-value array is not valid policy).
  assert {
    condition     = !can(regex("aws:PrincipalAccount", aws_organizations_policy.policy["rcp-data-perimeter"].content))
    error_message = "aws:PrincipalAccount must be omitted when no trusted accounts are configured"
  }

  # VPC BPA exclusions are disabled by default.
  assert {
    condition     = jsondecode(aws_organizations_policy.policy["declarative-ec2"].content).ec2_attributes.vpc_block_public_access.internet_gateway_block.exclusions_allowed["@@assign"] == "disabled"
    error_message = "VPC Block Public Access exclusions must be disabled by default"
  }
}

run "rcp_trusted_accounts_and_bpa_opt_in" {
  command = plan

  variables {
    data_perimeter_trusted_account_ids = ["222222222222"]
    allow_vpc_bpa_exclusions           = true
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "EnforceOrgIdentities"]).Condition.StringNotEqualsIfExists["aws:PrincipalAccount"] == ["222222222222"]
    error_message = "trusted account IDs must render into aws:PrincipalAccount"
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "ConfusedDeputyProtection"]).Condition.StringNotEqualsIfExists["aws:SourceAccount"] == ["222222222222"]
    error_message = "trusted account IDs must render into aws:SourceAccount"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["declarative-ec2"].content).ec2_attributes.vpc_block_public_access.internet_gateway_block.exclusions_allowed["@@assign"] == "enabled"
    error_message = "allow_vpc_bpa_exclusions = true must enable VPC BPA exclusions"
  }
}

run "region_list_renders_into_scp" {
  command = plan

  variables {
    allowed_regions = ["us-east-1", "eu-central-1"]
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.policy["scp-region-restriction"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"], "us-east-1")
    error_message = "allowed_regions list must render into the region-restriction SCP condition"
  }
}

run "attachments_key_correctly" {
  command = plan

  variables {
    attachments = {
      "baseline@root"        = { policy_key = "scp-baseline", target_id = "r-abcd" }
      "data-perimeter@wklds" = { policy_key = "rcp-data-perimeter", target_id = "ou-abcd-11111111" }
    }
  }

  assert {
    condition     = contains(keys(aws_organizations_policy_attachment.attach), "baseline@root")
    error_message = "attachments must key on the caller-provided map key"
  }
}

# Centralized root access: sts:AssumeRoot sessions (task-scoped, short-lived,
# issued from the management account / delegated admin) must survive the
# root-deny. Ordinary root sign-in carries no aws:AssumedRoot key, so the
# IfExists form keeps denying it.
run "root_deny_exempts_centralized_root_sessions" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyRootUserActions"]).Condition.BoolIfExists["aws:AssumedRoot"] == "false"
    error_message = "DenyRootUserActions must carry BoolIfExists aws:AssumedRoot=false so sts:AssumeRoot remediation sessions are not denied."
  }
}

# RCP web-identity tenant pins: absent by default, one statement per issuer
# when set, each Null-guarded so other issuers' tokens are unaffected.
run "federation_tenant_pins_off_by_default" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if startswith(s.Sid, "Pin")]) == 0
    error_message = "no federation pin statements without federation_tenant_pins."
  }

  assert {
    condition = alltrue([
      for sid in ["EnforceOrgIdentities", "ConfusedDeputyProtection"] :
      contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == sid]).Action, "ecr:*") &&
      contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == sid]).Action, "logs:*")
    ])
    error_message = "the RCP identity and confused-deputy statements must cover ECR and CloudWatch Logs."
  }
}

run "federation_tenant_pins_render" {
  command = plan

  variables {
    federation_tenant_pins = {
      tfc_organization = "acme"
      github_owners    = ["acme", "acme-apps"]
    }
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "PinTfcFederationToOrg"]).Action == "sts:AssumeRoleWithWebIdentity" &&
      one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "PinTfcFederationToOrg"]).Condition.Null["app.terraform.io:sub"] == "false" &&
      one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "PinTfcFederationToOrg"]).Condition.StringNotLike["app.terraform.io:sub"] == "organization:acme:*"
    )
    error_message = "the TFC pin must deny web identity whose app.terraform.io:sub is not organization:acme:* (Null-guarded)."
  }

  assert {
    condition     = one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "PinGithubFederationToOwners"]).Condition.StringNotLike["token.actions.githubusercontent.com:sub"] == ["repo:acme/*", "repo:acme-apps/*"]
    error_message = "the GitHub pin must allow only repo:<owner>/* subjects."
  }

  assert {
    condition     = length(aws_organizations_policy.policy["rcp-data-perimeter"].content) < 5120
    error_message = "the RCP with every pin and all built-in IdP denies must stay under the 5,120-character quota."
  }
}

# Central detection settings: with security accounts named, even the pipeline
# outside them is denied (only break-glass is exempt), and the SCP still fits.
run "central_detection_scoped_to_security_accounts" {
  command = plan

  variables {
    central_detection_account_ids = ["222222222222", "333333333333"]
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Condition.StringNotEquals["aws:PrincipalAccount"] == ["222222222222", "333333333333"] &&
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Action, "guardduty:CreateFilter") &&
      !contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Statement : s if s.Sid == "DenyCentralDetectionOutsideSecurityAccounts"]).Action, "config:PutConfigurationRecorder")
    )
    error_message = "GuardDuty/CloudTrail/Security Hub reconfiguration must be denied outside central_detection_account_ids; Config/flow logs stay with the workload pipeline."
  }

  assert {
    condition     = length(aws_organizations_policy.policy["scp-deny-tamper"].content) < 5120
    error_message = "deny-tamper SCP must stay under the 5,120-character SCP size quota with the central-detection statement."
  }
}

# The org-wide EC2 baseline carries no VPC BPA (that stays OU-scoped), and AI
# services are opted out everywhere.
run "baseline_declarative_and_ai_opt_out" {
  command = plan

  assert {
    condition = (
      !contains(keys(jsondecode(aws_organizations_policy.policy["declarative-ec2-baseline"].content).ec2_attributes), "vpc_block_public_access") &&
      jsondecode(aws_organizations_policy.policy["declarative-ec2-baseline"].content).ec2_attributes.instance_metadata_defaults.http_tokens["@@assign"] == "required" &&
      jsondecode(aws_organizations_policy.policy["aiservices-opt-out"].content).services.default.opt_out_policy["@@assign"] == "optOut" &&
      aws_organizations_policy.policy["aiservices-opt-out"].type == "AISERVICES_OPT_OUT_POLICY"
    )
    error_message = "declarative-ec2-baseline must enforce IMDSv2 without VPC BPA, and aiservices-opt-out must opt out by default."
  }
}

# policy_overrides replace or add; disabled_policies drop built-ins.
run "policy_overrides_and_disabled_policies" {
  command = plan

  variables {
    disabled_policies = ["backup-policy", "aiservices-opt-out"]
    policy_overrides = {
      "scp-region-restriction" = { type = "SERVICE_CONTROL_POLICY", content = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
      "scp-custom"             = { type = "SERVICE_CONTROL_POLICY", content = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
    }
  }

  assert {
    condition = (
      !contains(keys(aws_organizations_policy.policy), "backup-policy") &&
      !contains(keys(aws_organizations_policy.policy), "aiservices-opt-out") &&
      contains(keys(aws_organizations_policy.policy), "scp-custom") &&
      aws_organizations_policy.policy["scp-region-restriction"].content == "{\"Version\":\"2012-10-17\",\"Statement\":[]}" &&
      contains(keys(aws_organizations_policy.policy), "scp-deny-tamper")
    )
    error_message = "overrides must replace/add policies, disabled_policies must drop built-ins, and the rest must stay."
  }
}

# Replacing a core guardrail is allowed but always warns.
run "overriding_core_guardrail_warns" {
  command = plan

  variables {
    policy_overrides = {
      "scp-deny-tamper" = { type = "SERVICE_CONTROL_POLICY", content = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
    }
  }

  expect_failures = [check.core_guardrails_not_weakened]
}

# Built-in web-identity providers (no IAM provider resource) are denied unless
# allow-listed; IdP creation is denied to all but break-glass / StackSet exec;
# GitHub owner-ID subjects are allowed by the GitHub pin.
run "federation_completeness" {
  command = plan

  variables {
    federation_tenant_pins = {
      github_owner_ids          = ["123456"]
      allowed_builtin_providers = ["cognito-identity.amazonaws.com"]
    }
  }

  assert {
    condition = (
      length([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if startswith(s.Sid, "DenyBuiltinIdp")]) == 3 &&
      one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "DenyBuiltinIdpGraph"]).Condition.Null["graph.facebook.com:app_id"] == "false" &&
      one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "DenyBuiltinIdpAccounts"]).Condition.Null["accounts.google.com:aud"] == "false" &&
      contains(one([for s in jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement : s if s.Sid == "PinGithubFederationToOwners"]).Condition.StringNotLike["token.actions.githubusercontent.com:sub"], "repository_owner_id:123456:*")
    )
    error_message = "built-in IdPs must be denied unless allow-listed (with the right claim key), and GitHub owner-ID subjects must be allowed."
  }

  assert {
    condition = (
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyIdentityProviderChanges"]).Action, "iam:CreateOpenIDConnectProvider") &&
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-baseline"].content).Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Action, "ecr:TagResource") &&
      length(aws_organizations_policy.policy["scp-baseline"].content) < 5120 &&
      length(aws_organizations_policy.policy["rcp-data-perimeter"].content) < 5120
    )
    error_message = "the baseline SCP must deny IdP changes and ECR/Logs dp:* tagging, and both policies must fit the 5,120-character quota."
  }
}

# Global STS is never region-denied; ACM/KMS are allowed in us-east-1 for
# CloudFront certificates, and nowhere else outside the allowed regions.
run "region_restriction_allows_edge_and_global_sts" {
  command = plan

  assert {
    condition = (
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-region-restriction"].content).Statement : s if s.Sid == "DenyOutsideAllowedRegions"]).NotAction, "sts:*") &&
      contains(one([for s in jsondecode(aws_organizations_policy.policy["scp-region-restriction"].content).Statement : s if s.Sid == "EdgeCertificatesAndKeysOnlyInAllowedRegionsOrUsEast1"]).Condition.StringNotEquals["aws:RequestedRegion"], "us-east-1")
    )
    error_message = "sts must be exempt from the region deny, and ACM/KMS must be confined to the allowed regions plus us-east-1."
  }
}
