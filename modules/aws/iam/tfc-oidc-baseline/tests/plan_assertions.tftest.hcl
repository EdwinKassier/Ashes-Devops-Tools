# Plan-assertion tests for tfc-oidc-baseline.
#
# The template body is jsondecode'd so the trust policy is asserted
# structurally: exact sub per workspace and run phase, the aws.workload.identity
# audience, a literal (never wildcarded) organization, and a read-only plan role.

mock_provider "aws" {}

variables {
  tfc_organization = "acme"
  tfc_project      = "landing-zone"
  account_bindings = {
    security_tooling = { account_id = "222222222222", workspaces = ["aws-security"] }
    network          = { account_id = "444444444444", workspaces = ["aws-network"] }
    shared_services  = { account_id = "555555555555", workspaces = ["aws-identity", "aws-shared-services"], project = "platform" }
  }
  target_ou_ids = {
    Security       = "ou-abcd-security0"
    Infrastructure = "ou-abcd-infra0000"
  }
}

run "stack_set_is_service_managed_with_auto_deployment" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack_set.this.permission_model == "SERVICE_MANAGED"
    error_message = "the baseline must use a SERVICE_MANAGED StackSet (no per-account providers)"
  }

  assert {
    condition     = aws_cloudformation_stack_set.this.auto_deployment[0].enabled == true
    error_message = "auto-deployment must be on so accounts joining a targeted OU get the baseline"
  }

  assert {
    condition     = contains(aws_cloudformation_stack_set.this.capabilities, "CAPABILITY_NAMED_IAM")
    error_message = "named IAM roles require CAPABILITY_NAMED_IAM"
  }

  assert {
    condition     = length(aws_cloudformation_stack_set_instance.this) == 2 && aws_cloudformation_stack_set_instance.this["Security"].deployment_targets[0].organizational_unit_ids == toset(["ou-abcd-security0"])
    error_message = "one stack instance per targeted OU, keyed by OU name"
  }
}

run "oidc_provider_and_trust_conditions" {
  command = plan

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcOidcProvider.Properties.Url == "https://app.terraform.io"
    error_message = "the OIDC provider must be for https://app.terraform.io"
  }

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcOidcProvider.Properties.ClientIdList == ["aws.workload.identity"]
    error_message = "the OIDC provider audience must be aws.workload.identity"
  }

  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources.TfcOidcProvider.Properties), "ThumbprintList")
    error_message = "ThumbprintList is omitted by default"
  }

  # Plan role for security_tooling: exact sub for run_phase:plan, aud pinned.
  assert {
    condition = jsondecode(output.template_body).Resources.TfcPlanRoleSecurityTooling.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals["app.terraform.io:sub"] == [
      "organization:acme:project:landing-zone:workspace:aws-security:run_phase:plan"
    ]
    error_message = "the plan role must trust exactly organization:acme:project:landing-zone:workspace:aws-security:run_phase:plan"
  }

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcPlanRoleSecurityTooling.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals["app.terraform.io:aud"] == "aws.workload.identity"
    error_message = "the trust policy must pin aud = aws.workload.identity"
  }

  assert {
    condition = jsondecode(output.template_body).Resources.TfcApplyRoleSecurityTooling.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals["app.terraform.io:sub"] == [
      "organization:acme:project:landing-zone:workspace:aws-security:run_phase:apply"
    ]
    error_message = "the apply role must trust only the apply phase of its workspace"
  }

  # No StringLike (wildcard) operator by default.
  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources.TfcApplyRoleNetwork.Properties.AssumeRolePolicyDocument.Statement[0].Condition), "StringLike")
    error_message = "exact workspace names (StringEquals) are the default; StringLike must not appear"
  }

  # Project override + multiple workspaces.
  assert {
    condition = jsondecode(output.template_body).Resources.TfcApplyRoleSharedServices.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals["app.terraform.io:sub"] == [
      "organization:acme:project:platform:workspace:aws-identity:run_phase:apply",
      "organization:acme:project:platform:workspace:aws-shared-services:run_phase:apply",
    ]
    error_message = "per-binding project overrides and multi-workspace bindings must render exact subs"
  }

  # The organization segment is never wildcarded in any trust policy.
  assert {
    condition = alltrue(flatten([
      for k, s in output.trust_subjects : [for sub in concat(s.plan, s.apply) : startswith(sub, "organization:acme:project:") && !strcontains(sub, "*")]
    ]))
    error_message = "every sub must start with the literal organization and contain no wildcard"
  }

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcPlanRoleSecurityTooling.Properties.AssumeRolePolicyDocument.Statement[0].Principal.Federated.Ref == "TfcOidcProvider"
    error_message = "roles must trust the OIDC provider created by the same stack"
  }
}

run "plan_role_is_read_only_and_roles_are_account_scoped" {
  command = plan

  assert {
    condition     = jsonencode(jsondecode(output.template_body).Resources.TfcPlanRoleNetwork.Properties.ManagedPolicyArns) == jsonencode([{ "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/ReadOnlyAccess" }, { Ref = "TfcPlanDataReadDeny" }])
    error_message = "the plan role must carry only ReadOnlyAccess plus the read deny"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcPlanRole") || alltrue([for a in r.Properties.ManagedPolicyArns : !strcontains(try(a["Fn::Sub"], ""), "AdministratorAccess") && !strcontains(try(a["Fn::Sub"], ""), "PowerUserAccess")])
    ])
    error_message = "no plan role may carry a write policy"
  }

  assert {
    condition     = jsonencode(jsondecode(output.template_body).Resources.TfcApplyRoleNetwork.Properties.ManagedPolicyArns) == jsonencode([{ "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/AdministratorAccess" }])
    error_message = "the apply role defaults to AdministratorAccess"
  }

  # Each role pair is gated on its own account ID.
  assert {
    condition     = jsondecode(output.template_body).Resources.TfcPlanRoleNetwork.Condition == "IsNetwork" && jsondecode(output.template_body).Conditions.IsNetwork["Fn::Equals"][1] == "444444444444"
    error_message = "role pairs must be conditioned on AWS::AccountId so only the bound account gets them"
  }

  assert {
    condition     = length([for n, r in jsondecode(output.template_body).Resources : n if r.Type == "AWS::IAM::Role"]) == 6
    error_message = "three bindings must render exactly three plan/apply role pairs"
  }

  assert {
    condition     = output.plan_role_arns["network"] == "arn:aws:iam::444444444444:role/tfc-plan" && output.apply_role_arns["network"] == "arn:aws:iam::444444444444:role/tfc-apply"
    error_message = "role ARN outputs must be built from account ID + role name"
  }
}

run "workspace_wildcards_use_string_like_when_enabled" {
  command = plan

  variables {
    allow_workspace_wildcards = true
    account_bindings = {
      workload = { account_id = "888888888888", workspaces = ["aws-workload-*"] }
    }
  }

  assert {
    condition = jsondecode(output.template_body).Resources.TfcPlanRoleWorkload.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringLike["app.terraform.io:sub"] == [
      "organization:acme:project:landing-zone:workspace:aws-workload-*:run_phase:plan"
    ]
    error_message = "with wildcards enabled the sub must use StringLike, wildcard only in the workspace segment"
  }

  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources.TfcPlanRoleWorkload.Properties.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals), "app.terraform.io:sub")
    error_message = "the sub must not also appear under StringEquals"
  }

  assert {
    condition     = output.sub_condition_operator == "StringLike"
    error_message = "sub_condition_operator must report StringLike"
  }
}

run "no_bindings_deploys_only_the_oidc_providers" {
  command = plan

  variables {
    account_bindings = {}
  }

  assert {
    condition     = toset(keys(jsondecode(output.template_body).Resources)) == toset(["TfcOidcProvider", "GithubOidcProvider"]) && !contains(keys(jsondecode(output.template_body)), "Conditions")
    error_message = "with no bindings the template must contain only the TFC and GitHub OIDC providers and no empty Conditions section"
  }
}

run "apply_role_capped_by_embedded_boundary" {
  command = plan

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcApplyRole") || r.Properties.PermissionsBoundary == { Ref = "TfcApplyBoundary" }
    ])
    error_message = "every apply role must reference the embedded TfcApplyBoundary by default"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcPlanRole") || !contains(keys(r.Properties), "PermissionsBoundary")
    ])
    error_message = "the read-only plan role needs no boundary"
  }

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcApplyBoundary.Type == "AWS::IAM::ManagedPolicy" && jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.ManagedPolicyName == "tfc-apply-boundary"
    error_message = "the template must create exactly one tfc-apply-boundary managed policy"
  }

  # Allow-all base so legitimate Terraform is not blocked; only targeted denies.
  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Allow" && s.Action == "*" && s.Resource == "*"
    ])
    error_message = "the boundary must allow everything not explicitly denied"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Allow" || s.Action != "*"
    ])
    error_message = "no boundary deny may be a blanket Action = *"
  }

  assert {
    condition = alltrue([for a in [
      "organizations:LeaveOrganization",
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
      "guardduty:DeleteDetector", "guardduty:DisassociateFromAdministratorAccount",
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
      "iam:CreateUser", "iam:CreateAccessKey",
      ] : anytrue([
        for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
        s.Effect == "Deny" && contains(flatten([s.Action]), a)
    ])])
    error_message = "the boundary must deny leaving the org, disabling CloudTrail/GuardDuty/Config, and creating IAM users/access keys"
  }

  # Self-protection: the roles, the OIDC provider and the boundary itself.
  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Sid == "DenyTamperingWithTfcBaseline" &&
      contains(s.Action, "iam:UpdateAssumeRolePolicy") && contains(s.Action, "iam:DeleteRolePermissionsBoundary") && contains(s.Action, "iam:CreatePolicyVersion") &&
      toset([for r in s.Resource : r["Fn::Sub"]]) == toset([
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/tfc-plan",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/tfc-apply",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:oidc-provider/app.terraform.io",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:policy/tfc-apply-boundary",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:policy/tfc-plan-data-read-deny",
      ])
    ])
    error_message = "the boundary must stop the apply role tampering with the TFC roles, OIDC provider, the boundary or the plan-role read deny"
  }

  assert {
    condition     = output.apply_permissions_boundary == "embedded:tfc-apply-boundary"
    error_message = "apply_permissions_boundary output must report the embedded boundary"
  }

  assert {
    condition     = length(output.template_body) <= 51200
    error_message = "template with boundary must stay within the inline template limit"
  }
}

run "external_boundary_arn_used_when_supplied" {
  command = plan

  variables {
    apply_permissions_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  }

  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources), "TfcApplyBoundary") && jsondecode(output.template_body).Resources.TfcApplyRoleNetwork.Properties.PermissionsBoundary == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "a supplied boundary ARN must replace the embedded boundary"
  }
}

# A supplied external boundary is as protected as the embedded one: the
# apply identity must not be able to rewrite or delete the policy that caps it.
run "external_boundary_is_protected" {
  command = plan

  variables {
    apply_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/org-apply-boundary"
  }

  assert {
    condition     = contains(local.baseline_protected_arns, "arn:aws:iam::111111111111:policy/org-apply-boundary")
    error_message = "an external apply_permissions_boundary_arn must be in baseline_protected_arns."
  }

  assert {
    condition     = !contains(local.baseline_protected_arns, local.apply_boundary_arn_sub)
    error_message = "the unused embedded boundary ARN must not be listed when an external boundary replaces it."
  }
}

run "external_boundary_mode_attaches_tamper_deny_to_apply_role" {
  command = plan

  variables {
    apply_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/org-apply-boundary"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcApplyRole") || (
        length(r.Properties.Policies) == 1 &&
        r.Properties.Policies[0].PolicyDocument.Statement[0].Sid == "DenyTamperingWithTfcBaseline" &&
        contains(r.Properties.Policies[0].PolicyDocument.Statement[0].Action, "iam:PutRolePolicy") &&
        contains(r.Properties.Policies[0].PolicyDocument.Statement[0].Action, "iam:DeleteRolePolicy") &&
        contains([for x in r.Properties.Policies[0].PolicyDocument.Statement[0].Resource : x["Fn::Sub"]], "arn:aws:iam::111111111111:policy/org-apply-boundary")
      )
    ])
    error_message = "with an external boundary the tamper deny must be inline on every apply role."
  }
}

run "embedded_boundary_mode_has_no_inline_tamper_deny" {
  command = plan

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcApplyRole") || !contains(keys(r.Properties), "Policies")
    ])
    error_message = "embedded mode carries the tamper deny in the boundary, not inline."
  }

  assert {
    condition     = length([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyTamperingWithTfcBaseline"]) == 1
    error_message = "the embedded boundary must carry exactly one tamper deny."
  }
}

run "embedded_boundary_is_protected_by_default" {
  command = plan

  assert {
    condition     = contains(local.baseline_protected_arns, local.apply_boundary_arn_sub) && length(local.baseline_protected_arns) == 5
    error_message = "by default the embedded boundary and the plan-role deny are among the five protected ARNs."
  }
}

run "boundary_can_be_disabled" {
  command = plan

  variables {
    enable_apply_permissions_boundary = false
  }

  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources), "TfcApplyBoundary") && !contains(keys(jsondecode(output.template_body).Resources.TfcApplyRoleNetwork.Properties), "PermissionsBoundary") && output.apply_permissions_boundary == null
    error_message = "disabling the boundary must remove it from the template and the apply role"
  }
}

run "apply_boundary_propagates_to_created_roles" {
  # The apply identity must not escape its boundary by creating an
  # unbounded role (or granting to one) and assuming it.
  command = plan

  assert {
    condition = one([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyRoleWithoutApplyBoundary"
      ]).Effect == "Deny" && length(setsubtract(
      ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:PutRolePolicy"],
      one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyRoleWithoutApplyBoundary"]).Action
    )) == 0
    error_message = "the boundary must deny CreateRole/PutRolePermissionsBoundary/AttachRolePolicy/PutRolePolicy on roles lacking the same boundary"
  }

  assert {
    condition     = endswith(one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyRoleWithoutApplyBoundary"]).Condition.StringNotEquals["iam:PermissionsBoundary"]["Fn::Sub"], ":policy/tfc-apply-boundary")
    error_message = "the propagation condition must pin iam:PermissionsBoundary to the embedded boundary's own ARN"
  }

  assert {
    condition     = contains(one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyPermissionsBoundaryRemoval"]).Action, "iam:DeleteRolePermissionsBoundary") && one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyPermissionsBoundaryRemoval"]).Resource == "*"
    error_message = "the boundary must deny removing any role's permissions boundary"
  }

  # IAM managed-policy size quota (6,144 characters, whitespace excluded).
  assert {
    condition     = length(jsonencode(jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument)) < 6144
    error_message = "the embedded boundary must stay under the 6,144-character managed-policy quota"
  }
}

run "boundary_propagation_can_be_disabled" {
  command = plan

  variables {
    enable_apply_boundary_propagation = false
  }

  assert {
    condition     = length([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyRoleWithoutApplyBoundary"]) == 0
    error_message = "enable_apply_boundary_propagation = false must omit the propagation statements"
  }
}

run "plan_role_denies_data_plane_reads" {
  # ReadOnlyAccess grants data reads; every plan role gets the shared deny
  # managed policy (one per account, so the template does not grow per binding).
  command = plan

  assert {
    condition = (
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Type == "AWS::IAM::ManagedPolicy" &&
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.ManagedPolicyName == "tfc-plan-data-read-deny" &&
      !contains(keys(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny), "Condition") &&
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Effect == "Deny" &&
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Resource == "*" &&
      length(setsubtract(
        ["s3:GetObject*", "secretsmanager:GetSecretValue", "ssm:GetParameter*", "kms:Decrypt", "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan", "sqs:ReceiveMessage", "kinesis:GetRecords", "logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery", "rds-data:*", "athena:GetQueryResults"],
        jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action
      )) == 0
    )
    error_message = "the account must carry the data-plane read deny managed policy on all resources"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcPlanRole") || (
        contains(r.Properties.ManagedPolicyArns, { Ref = "TfcPlanDataReadDeny" }) &&
        !contains(keys(r.Properties), "Policies")
      )
    ])
    error_message = "every plan role must attach the deny managed policy"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcApplyRole") || (!contains(keys(r.Properties), "Policies") && !contains(r.Properties.ManagedPolicyArns, { Ref = "TfcPlanDataReadDeny" }))
    ])
    error_message = "the data-plane deny applies to the plan role only"
  }

  # The apply role must not detach or re-version the plan role's deny.
  assert {
    condition     = contains(local.baseline_protected_arns, local.plan_read_deny_arn_sub)
    error_message = "the plan-role deny policy must be in the apply role's tamper-protected set"
  }
}

run "plan_role_data_read_exemptions_render_as_not_resource" {
  command = plan

  variables {
    plan_role_data_read_exempt_arns = ["arn:aws:secretsmanager:eu-west-2:444444444444:secret:supabase-connection-*"]
  }

  assert {
    condition = (
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].NotResource == ["arn:aws:secretsmanager:eu-west-2:444444444444:secret:supabase-connection-*"] &&
      !contains(keys(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0]), "Resource")
    )
    error_message = "exempt ARNs must render as NotResource (and replace Resource = *)"
  }
}

run "plan_role_data_plane_deny_covers_log_and_secret_read_paths" {
  command = plan

  assert {
    condition = (
      alltrue([for a in [
        "ssm:GetCommandInvocation", "logs:GetLogRecord", "logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery",
        "rds:DownloadDBLogFilePortion", "es:ESHttpGet", "cassandra:Select", "codecommit:GitPull", "codecommit:GetFile",
        "s3:GetObject*", "secretsmanager:BatchGetSecretValue", "kms:GenerateDataKey*",
        ] : contains(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action, a)
      ]) &&
      !anytrue([for a in ["lambda:GetFunction", "apigateway:GET"] : contains(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action, a)]) &&
      length(jsonencode(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument)) < 6144
    )
    error_message = "member plan roles must deny the full data-plane read set (never refresh-needed reads) within the inline size limit."
  }
}

run "plan_role_data_read_deny_can_be_disabled" {
  command = plan

  variables {
    enable_plan_role_data_read_deny = false
  }

  assert {
    condition = (
      !contains(keys(jsondecode(output.template_body).Resources), "TfcPlanDataReadDeny") &&
      !contains(jsondecode(output.template_body).Resources.TfcPlanRoleNetwork.Properties.ManagedPolicyArns, { Ref = "TfcPlanDataReadDeny" })
    )
    error_message = "enable_plan_role_data_read_deny = false must omit the deny policy and its attachment"
  }
}

run "apply_boundary_blocks_privileged_role_squatting_and_security_teardown" {
  # N1(c): even with boundary-carrying CreateRole allowed by propagation, the
  # apply identity must not create/modify/pass the break-glass, OAAR or
  # StackSet-execution roles, tamper with protected KMS keys, touch dp:* tags,
  # or disable Security Hub / Macie / Inspector / Access Analyzer.
  command = plan

  assert {
    condition = (
      length(setsubtract(
        ["iam:CreateRole", "iam:UpdateAssumeRolePolicy", "iam:AttachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRole", "iam:PassRole"],
        one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]).Action
      )) == 0 &&
      toset([for r in one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]).Resource : r["Fn::Sub"]]) == toset([
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/break-glass",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/OrganizationAccountAccessRole",
        "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/stacksets-exec-*",
      ])
    )
    error_message = "the boundary must deny create/trust/attach/delete/pass on the break-glass, OAAR and stacksets-exec-* roles"
  }

  assert {
    condition = (
      length(setsubtract(
        ["kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy"],
        one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyProtectedKeyTampering"]).Action
      )) == 0 &&
      one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyProtectedKeyTampering"]).Condition.StringEquals["aws:ResourceTag/protected"] == "true" &&
      one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyProtectedKeyUntag"]).Condition["ForAnyValue:StringEquals"]["aws:TagKeys"] == "protected"
    )
    error_message = "the boundary must deny destruction / policy rewrite / untag of keys tagged protected=true"
  }

  assert {
    condition = (
      one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Condition["ForAnyValue:StringLike"]["aws:TagKeys"] == "dp:*" &&
      length(setsubtract(
        ["iam:CreateRole", "iam:TagRole", "s3:PutBucketTagging", "kms:TagResource", "sqs:TagQueue", "secretsmanager:TagResource"],
        one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyDataPerimeterTagTampering"]).Action
      )) == 0
    )
    error_message = "the boundary must deny setting or removing dp:* data-perimeter tags"
  }

  assert {
    condition = length(setsubtract(
      ["securityhub:Disable*", "securityhub:BatchDisableStandards", "macie2:DisableMacie", "inspector2:Disable", "access-analyzer:DeleteAnalyzer", "guardduty:DeleteMembers"],
      one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyDisablingDetectiveControls"]).Action
    )) == 0
    error_message = "the boundary must deny disabling Security Hub / Macie / Inspector / Access Analyzer"
  }

  # IAM managed-policy size quota (6,144 characters, whitespace excluded).
  assert {
    condition     = length(jsonencode(jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument)) < 6144
    error_message = "the embedded boundary must stay under the 6,144-character managed-policy quota"
  }
}

run "plan_role_denies_secret_bearing_reads_not_needed_for_refresh" {
  # Actions that leak secrets and are never used by Terraform refresh.
  command = plan

  assert {
    condition = length(setsubtract(
      ["ec2:GetPasswordData", "kms:GenerateDataKey*", "secretsmanager:BatchGetSecretValue", "glue:GetConnection", "glue:GetConnections"],
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action
    )) == 0
    error_message = "the plan-role deny must cover GetPasswordData, GenerateDataKey*, BatchGetSecretValue and Glue connection reads"
  }

  # ssm:GetParameter* covers GetParameterHistory.
  assert {
    condition     = contains(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action, "ssm:GetParameter*")
    error_message = "ssm:GetParameter* (incl. GetParameterHistory) must be denied"
  }

  # Refresh-critical reads stay allowed so plans keep working.
  assert {
    condition = alltrue([
      for a in ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "ecs:DescribeTaskDefinition", "ec2:DescribeInstanceAttribute"] :
      !contains(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action, a)
    ])
    error_message = "refresh-critical reads (lambda:GetFunction*, ecs:DescribeTaskDefinition, ec2:DescribeInstanceAttribute) must not be denied"
  }
}

run "member_break_glass_stack_set_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudformation_stack_set.break_glass) == 0 && length(aws_cloudformation_stack_set_instance.break_glass) == 0 && output.member_break_glass_stack_set_name == null
    error_message = "the member break-glass StackSet is opt-in at module level"
  }
}

run "member_break_glass_role_occupies_the_name_with_mfa_trust" {
  # N1(b): the SCP-exempt break-glass name is occupied in every member account
  # by a role that only the management-account break-glass principal can
  # assume, with MFA.
  command = plan

  variables {
    enable_member_break_glass_role            = true
    break_glass_role_name                     = "emergency/break-glass"
    member_break_glass_trusted_principal_arns = ["arn:aws:iam::111111111111:role/break-glass"]
    member_break_glass_target_ou_ids          = { root = "r-abcd" }
  }

  assert {
    condition     = aws_cloudformation_stack_set.break_glass[0].permission_model == "SERVICE_MANAGED" && aws_cloudformation_stack_set.break_glass[0].auto_deployment[0].enabled == true
    error_message = "the member break-glass StackSet must be service-managed with auto-deployment"
  }

  assert {
    condition     = aws_cloudformation_stack_set_instance.break_glass["root"].deployment_targets[0].organizational_unit_ids == toset(["r-abcd"])
    error_message = "the member break-glass StackSet must target the configured root/OUs"
  }

  assert {
    condition = (
      jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.RoleName == "break-glass" &&
      jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.Path == "/emergency/"
    )
    error_message = "a path-prefixed break-glass name must split into Path + RoleName"
  }

  assert {
    condition = (
      jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Principal.AWS == ["arn:aws:iam::111111111111:role/break-glass"] &&
      jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true" &&
      jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties.AssumeRolePolicyDocument.Statement[0].Condition.NumericLessThan["aws:MultiFactorAuthAge"] == "3600"
    )
    error_message = "the member break-glass role must trust only the management break-glass principal, with MFA"
  }

  assert {
    condition     = !contains(keys(jsondecode(output.member_break_glass_template_body).Resources.MemberBreakGlassRole.Properties), "PermissionsBoundary")
    error_message = "the member break-glass role must not carry the tfc-apply boundary"
  }

  # The boundary protects the path-prefixed name too.
  assert {
    condition     = contains([for r in one([for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement : s if s.Sid == "DenyPrivilegedRoleTampering"]).Resource : r["Fn::Sub"]], "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/emergency/break-glass")
    error_message = "the boundary must protect the configured (path-prefixed) break-glass name"
  }
}

run "member_break_glass_requires_a_trusted_principal" {
  command = plan

  variables {
    enable_member_break_glass_role   = true
    member_break_glass_target_ou_ids = { root = "r-abcd" }
  }

  expect_failures = [aws_cloudformation_stack_set.break_glass]
}

# The pipeline may not register trust anchors: a new OIDC/SAML provider plus a
# role (carrying the boundary, granted admin) trusting it is a persistence path.
run "boundary_denies_new_identity_providers" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Sid == "DenyNewIdentityProviders" && s.Effect == "Deny" && s.Resource == "*" &&
      contains(s.Action, "iam:CreateOpenIDConnectProvider") && contains(s.Action, "iam:CreateSAMLProvider") &&
      contains(s.Action, "iam:AddClientIDToOpenIDConnectProvider")
    ])
    error_message = "the apply boundary must deny creating OIDC/SAML providers and adding audiences, on every resource."
  }

  # The GitHub provider app-services relies on is owned by the StackSet instead.
  assert {
    condition = (
      jsondecode(output.template_body).Resources.GithubOidcProvider.Properties.Url == "https://token.actions.githubusercontent.com" &&
      jsondecode(output.template_body).Resources.GithubOidcProvider.Properties.ClientIdList == ["sts.amazonaws.com"]
    )
    error_message = "the StackSet must create the account-wide GitHub OIDC provider (aud sts.amazonaws.com) by default."
  }
}

run "github_provider_opt_out" {
  command = plan

  variables {
    create_github_oidc_provider = false
  }

  assert {
    condition     = !contains(keys(jsondecode(output.template_body).Resources), "GithubOidcProvider")
    error_message = "create_github_oidc_provider = false must omit the GitHub provider."
  }
}

# Secret-bearing reads that ReadOnlyAccess grants and that Terraform refresh of
# the resources this repo manages never calls.
run "plan_role_denies_secret_bearing_control_plane_reads" {
  command = plan

  assert {
    condition = length(setsubtract(
      [
        "ec2:GetLaunchTemplateData", "ec2:DescribeLaunchTemplateVersions", "autoscaling:DescribeLaunchConfigurations",
        "codebuild:BatchGetProjects", "codebuild:BatchGetBuilds", "lambda:GetLayerVersion",
        "cognito-idp:DescribeUserPoolClient", "appsync:ListApiKeys", "states:GetExecutionHistory", "states:DescribeExecution",
        "lightsail:GetInstanceAccessDetails", "lightsail:GetRelationalDatabaseMasterUserPassword",
        "glacier:GetJobOutput", "elasticbeanstalk:DescribeConfigurationSettings",
        "ecr:GetAuthorizationToken", "codecommit:GetBlob", "codeartifact:ReadFromRepository", "timestream:Select",
      ],
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[0].Action
    )) == 0
    error_message = "the plan-role deny must cover launch-template user data, CodeBuild env vars, Cognito/AppSync secrets, Step Functions data, Lightsail, Glacier and Beanstalk reads"
  }

  # API key values: apigateway:GET denied on the key paths only, so refresh of
  # HTTP APIs (also apigateway:GET) keeps working.
  assert {
    condition = (
      one([for st in jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement : st if st.Sid == "DenyApiKeyValueReads"]).Effect == "Deny" &&
      one([for st in jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement : st if st.Sid == "DenyApiKeyValueReads"]).Action == "apigateway:GET" &&
      [for x in one([for st in jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement : st if st.Sid == "DenyApiKeyValueReads"]).Resource : x["Fn::Sub"]] == [
        "arn:$${AWS::Partition}:apigateway:*::/apikeys",
        "arn:$${AWS::Partition}:apigateway:*::/apikeys/*",
        "arn:$${AWS::Partition}:apigateway:*::/usageplans/*/keys",
        "arn:$${AWS::Partition}:apigateway:*::/usageplans/*/keys/*",
      ]
    )
    error_message = "every plan role must deny apigateway:GET on the API key and usage-plan key paths only"
  }

  # IAM managed-policy quota (6,144 characters) and the inline template limit.
  assert {
    condition = (
      length(jsonencode(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument)) < 6144 &&
      length(output.template_body) <= 51200
    )
    error_message = "the plan-role deny must fit the 6,144-character managed-policy quota and the template the inline template limit"
  }
}

run "plan_role_api_key_deny_kept_with_exemptions" {
  command = plan

  variables {
    plan_role_data_read_exempt_arns = ["arn:aws:secretsmanager:eu-west-2:444444444444:secret:supabase-connection-*"]
  }

  assert {
    condition = (
      length(jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement) == 2 &&
      jsondecode(output.template_body).Resources.TfcPlanDataReadDeny.Properties.PolicyDocument.Statement[1].Sid == "DenyApiKeyValueReads"
    )
    error_message = "data-read exemptions must not drop the API key deny"
  }
}

# Template growth: the deny is one managed policy per account, not per role,
# so a large estate (24 bound accounts) still fits the inline template limit.
run "template_fits_with_many_bindings" {
  command = plan

  variables {
    account_bindings = { for i in range(24) : "acct_${i}" => { account_id = format("1000000000%02d", i), workspaces = ["aws-workload-env${i}"] } }
  }

  assert {
    condition     = length(output.template_body) <= 51200
    error_message = "the template with 24 bindings must stay within the 51,200-byte inline template limit"
  }
}
