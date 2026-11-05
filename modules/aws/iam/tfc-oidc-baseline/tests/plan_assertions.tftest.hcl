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
    condition     = jsondecode(output.template_body).Resources.TfcPlanRoleNetwork.Properties.ManagedPolicyArns == ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    error_message = "the plan role must carry only ReadOnlyAccess"
  }

  assert {
    condition = alltrue([
      for name, r in jsondecode(output.template_body).Resources :
      !startswith(name, "TfcPlanRole") || alltrue([for a in r.Properties.ManagedPolicyArns : !strcontains(a, "AdministratorAccess") && !strcontains(a, "PowerUserAccess")])
    ])
    error_message = "no plan role may carry a write policy"
  }

  assert {
    condition     = jsondecode(output.template_body).Resources.TfcApplyRoleNetwork.Properties.ManagedPolicyArns == ["arn:aws:iam::aws:policy/AdministratorAccess"]
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

run "no_bindings_deploys_only_the_oidc_provider" {
  command = plan

  variables {
    account_bindings = {}
  }

  assert {
    condition     = keys(jsondecode(output.template_body).Resources) == ["TfcOidcProvider"] && !contains(keys(jsondecode(output.template_body)), "Conditions")
    error_message = "with no bindings the template must contain only the OIDC provider and no empty Conditions section"
  }
}
