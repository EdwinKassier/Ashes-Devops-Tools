# Plan-assertion tests for the aws-organization stage.
#
# Uses mock_provider so no AWS credentials are required. module.organization is
# overridden with known root/OU/organization IDs so that (a) the guardrail
# attachment for_each targets and the org-identity/account-id inputs to the
# policy module are known at plan, and (b) the assertions on plan-known output
# keys are non-vacuous.

mock_provider "aws" {}

variables {
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
  tfc_organization        = "acme"
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
