# Plan assertions for tfc-management-roles: one exact-sub role per workspace and
# run phase, least-privilege apply policies, and org-takeover / member-pivot
# denies on every role.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  tfc_organization = "acme"
  tfc_project      = "landing-zone-aws"
}

run "one_role_pair_per_workspace_with_exact_trust" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.this)) == toset(["aws-security:plan", "aws-security:apply", "aws-backup:plan", "aws-backup:apply"])
    error_message = "aws-security and aws-backup must each get a plan and an apply role."
  }

  assert {
    condition = (
      aws_iam_role.this["aws-backup:apply"].name == "tfc-mgmt-aws-backup-apply" &&
      jsondecode(aws_iam_role.this["aws-backup:apply"].assume_role_policy).Statement[0].Condition.StringEquals["app.terraform.io:sub"] == "organization:acme:project:landing-zone-aws:workspace:aws-backup:run_phase:apply" &&
      jsondecode(aws_iam_role.this["aws-backup:apply"].assume_role_policy).Statement[0].Condition.StringEquals["app.terraform.io:aud"] == "aws.workload.identity" &&
      jsondecode(aws_iam_role.this["aws-backup:apply"].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"
    )
    error_message = "each role must trust exactly one workspace and run phase (StringEquals sub + aud) via the management OIDC provider."
  }
}

run "apply_policies_are_least_privilege" {
  command = plan

  # Backup may only write BACKUP_POLICY organization policies.
  assert {
    condition     = one([for s in jsondecode(output.apply_policies["aws-backup"]).Statement : s if s.Sid == "BackupPolicyOnly"]).Condition.StringEquals["organizations:PolicyType"] == "BACKUP_POLICY"
    error_message = "aws-backup's org-policy writes must be conditioned on organizations:PolicyType = BACKUP_POLICY."
  }

  assert {
    condition     = !anytrue([for s in jsondecode(output.apply_policies["aws-backup"]).Statement : s.Effect == "Allow" && contains(flatten([s.Action]), "iam:*Role")])
    error_message = "aws-backup must not be able to manage IAM roles."
  }

  # Every apply policy denies the member-account pivot and org takeover.
  assert {
    condition = alltrue([
      for ws in ["aws-security", "aws-backup"] :
      contains(one([for s in jsondecode(output.apply_policies[ws]).Statement : s if s.Sid == "DenyMemberAccountPivot"]).Resource, "arn:aws:iam::*:role/OrganizationAccountAccessRole") &&
      contains(one([for s in jsondecode(output.apply_policies[ws]).Statement : s if s.Sid == "DenyOrgTakeover"]).Action, "organizations:CreateAccount") &&
      contains(one([for s in jsondecode(output.apply_policies[ws]).Statement : s if s.Sid == "DenyManagementRoleTampering"]).Resource, "arn:aws:iam::111111111111:role/tfc-mgmt-*")
    ])
    error_message = "every apply role must deny assuming OrganizationAccountAccessRole, creating accounts and editing the management roles."
  }

  # The plan role carries the same guard denies next to ReadOnlyAccess.
  assert {
    condition = (
      aws_iam_role_policy_attachment.read_only["aws-security:plan"].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess" &&
      anytrue([for s in jsondecode(aws_iam_role_policy.plan_guard["aws-security:plan"].policy).Statement : s.Sid == "DenyMemberAccountPivot"])
    )
    error_message = "plan roles must be ReadOnlyAccess plus the guard denies."
  }
}

run "custom_workspace_policy" {
  command = plan

  variables {
    workspaces = {
      "aws-security" = { project = "security" }
      "aws-audit"    = { apply_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
    }
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.this["aws-security:plan"].assume_role_policy).Statement[0].Condition.StringEquals["app.terraform.io:sub"] == "organization:acme:project:security:workspace:aws-security:run_phase:plan" &&
      output.apply_policies["aws-audit"] == "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    )
    error_message = "per-workspace project and apply_policy_json must be honoured."
  }
}

# The management roles deny exactly the identity-provider actions the member
# apply boundary denies (tfc-oidc-baseline DenyNewIdentityProviders).
run "identity_provider_denies_match_member_boundary" {
  command = plan

  assert {
    condition = toset([
      for a in one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DenyOrgTakeover"]).Action : a
      if startswith(a, "iam:") && (strcontains(a, "OpenIDConnectProvider") || strcontains(a, "SAMLProvider"))
      ]) == toset([
      "iam:CreateOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
    ])
    error_message = "the management roles' identity-provider denies must equal the member boundary's DenyNewIdentityProviders set."
  }
}

# The aws-security role must not hold IAM writes on arbitrary roles in the
# management account (create role + attach admin + assume = org takeover).
run "security_iam_writes_scoped_to_trail_role" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(output.apply_policies["aws-security"]).Statement :
      !(s.Effect == "Allow" && anytrue([for a in flatten([s.Action]) : startswith(a, "iam:") && a != "iam:CreateServiceLinkedRole"]) && contains(flatten([s.Resource]), "*"))
    ])
    error_message = "aws-security must have no IAM write allowed on Resource *."
  }

  assert {
    condition = (
      one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "PassTrailDeliveryRoleToCloudTrail"]).Resource == ["arn:aws:iam::111111111111:role/org-trail-cloudwatch-delivery"] &&
      length([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Effect == "Allow" && anytrue([for a in flatten([s.Action]) : contains(["iam:CreateRole", "iam:PutRolePolicy", "iam:AttachRolePolicy", "iam:UpdateAssumeRolePolicy"], a)])]) == 0 &&
      !contains(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "SecurityServicesDelegationOnly"]).Condition.StringEquals["organizations:ServicePrincipal"], "sso.amazonaws.com") &&
      !contains(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "SecurityServicesDelegationOnly"]).Condition.StringEquals["organizations:ServicePrincipal"], "member.org.stacksets.cloudformation.amazonaws.com") &&
      contains(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DenyTrailAndKeyDestruction"]).Action, "cloudtrail:StopLogging") &&
      anytrue([for r in one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DenyManagementRoleTampering"]).Resource : endswith(r, ":role/OrganizationBreakGlass")])
    )
    error_message = "aws-security must have no IAM role writes (only PassRole of the trail delivery role), delegation only for security services, trail/key destruction denied and break-glass protected."
  }
}

run "plan_roles_deny_data_plane_reads" {
  command = plan

  assert {
    condition     = contains(one([for s in jsondecode(aws_iam_role_policy.plan_guard["aws-backup:plan"].policy).Statement : s if s.Sid == "DenyDataPlaneReads"]).Action, "secretsmanager:GetSecretValue")
    error_message = "management plan roles must deny data-plane reads like the member tfc-plan roles."
  }
}

run "security_trail_permissions_scoped_to_org_trail" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "OrganizationTrailOnly"]).Resource == ["arn:aws:cloudtrail:*:111111111111:trail/org-trail"]
    error_message = "cloudtrail:* must be scoped to the organization trail ARN."
  }
}

# The aws-security role reaches only the org trail's own log group, topics and
# owner-tagged keys, and delegates only to the listed security accounts.
run "security_wiring_scoped_to_trail_resources" {
  command = plan

  variables {
    delegated_admin_account_ids = ["222222222222"]
  }

  assert {
    condition = (
      !anytrue([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s.Effect == "Allow" && contains(flatten([s.Resource]), "*") && anytrue([for a in flatten([s.Action]) : contains(["kms:*", "logs:*", "sns:*", "cloudtrail:*"], a)]) && !can(s.Condition)]) &&
      one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "CreateOwnedKeysOnly"]).Condition.StringEquals["aws:RequestTag/Workspace"] == "aws-security" &&
      one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DelegateOnlyToSecurityAccounts"]).Resource == ["arn:aws:organizations::111111111111:account/o-*/222222222222"] &&
      !contains(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "SecurityServicesDelegationOnly"]).Condition.StringEquals["organizations:ServicePrincipal"], "account.amazonaws.com")
    )
    error_message = "kms/logs/sns/cloudtrail wildcards must be scoped (resource or tag condition), and delegation pinned to the security accounts."
  }
}

# Trail repointing and key-policy rewrites are break-glass only; alarms are
# limited to the trail's own; delegation fails closed without an account.
run "security_role_cannot_quietly_defeat_audit" {
  command = plan

  assert {
    condition = (
      length(setintersection(toset(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DenyTrailAndKeyDestruction"]).Action), toset(["cloudtrail:UpdateTrail", "kms:PutKeyPolicy", "kms:CreateGrant", "kms:DisableKeyRotation"]))) == 4 &&
      one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "TrailAlarmsOnly"]).Resource == ["arn:aws:cloudwatch:*:111111111111:alarm:org-trail-*"] &&
      contains(one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "CreateOwnedKeysOnly"]).Action, "kms:TagResource") &&
      one([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s if s.Sid == "DelegateOnlyToSecurityAccounts"]).Resource == ["arn:aws:organizations::111111111111:account/o-*/none"]
    )
    error_message = "UpdateTrail / PutKeyPolicy / CreateGrant / DisableKeyRotation must be denied, alarms scoped to the trail, create-time tagging allowed, and delegation fail closed."
  }
}

run "no_tag_based_kms_access" {
  command = plan

  variables {
    tags = { Team = "platform" }
  }

  assert {
    condition     = !anytrue([for s in jsondecode(output.apply_policies["aws-security"]).Statement : s.Sid == "OwnedKeysOnly"])
    error_message = "No statement may grant kms:* on keys by resource tag; tags must grant nothing."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(output.apply_policies["aws-security"]).Statement :
      s.Effect == "Allow" && try(contains(flatten([s.Action]), "kms:*"), false)
    ])
    error_message = "The aws-security apply role must hold no Allow kms:*."
  }

  # No aws:TagKeys allow-list: the provider default_tags would deny CreateKey.
  assert {
    condition = anytrue([
      for s in jsondecode(output.apply_policies["aws-security"]).Statement :
      s.Sid == "CreateOwnedKeysOnly" && toset(keys(s.Condition)) == toset(["StringEquals"]) &&
      !can(s.Condition.StringEquals["aws:TagKeys"]) && !can(s.Condition["ForAllValues:StringEquals"])
    ])
    error_message = "CreateOwnedKeysOnly must be conditioned only on the owner request tag, with no aws:TagKeys restriction."
  }
}
