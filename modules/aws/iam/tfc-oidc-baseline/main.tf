# tfc-oidc-baseline
#
# Deploys, FROM THE MANAGEMENT (or CloudFormation delegated-admin) ACCOUNT, a
# Terraform Cloud workload-identity baseline into member accounts — without a
# Terraform provider per account. A SERVICE_MANAGED CloudFormation StackSet
# (auto-deploying to accounts that join the targeted OUs) creates in each member:
#
#   - AWS::IAM::OIDCProvider for https://<tfc_hostname> (aud aws.workload.identity)
#   - <plan_role_name>  (default tfc-plan)  — read-only; trusts ONLY
#       <host>:sub = organization:<org>:project:<project>:workspace:<ws>:run_phase:plan
#   - <apply_role_name> (default tfc-apply) — apply policy; trusts ONLY
#       <host>:sub = organization:<org>:project:<project>:workspace:<ws>:run_phase:apply
#
# One template serves every account. Per-account workspace scoping is compiled
# into the template as CloudFormation Conditions keyed on AWS::AccountId, so a
# bound account gets exactly one plan/apply role pair trusting exactly its own
# workspaces, and an unbound account in a targeted OU gets only the (inert) OIDC
# provider. Policy JSON is built with jsonencode (CLAUDE.md AWS rule 3) so tests
# can jsondecode and assert on the trust conditions.
#
# The management account is NOT covered: service-managed StackSets never deploy
# to it. The management-account role the aws-organization workspace uses is a
# phase-0, human-created bootstrap role (docs/runbooks/aws-bootstrap.md).

locals {
  aud_key = "${var.tfc_hostname}:aud"
  sub_key = "${var.tfc_hostname}:sub"

  # StringLike only when workspace wildcards are explicitly allowed. The org and
  # project segments are validated wildcard-free either way.
  sub_operator = var.allow_workspace_wildcards ? "StringLike" : "StringEquals" # surfaced as an output

  # CloudFormation logical-ID suffix per binding key: security_tooling -> SecurityTooling.
  logical_suffix = {
    for k in keys(var.account_bindings) : k => join("", [for p in split("_", replace(k, "-", "_")) : title(p)])
  }

  subjects = {
    for k, b in var.account_bindings : k => {
      for phase in ["plan", "apply"] : phase => [
        for ws in b.workspaces :
        "organization:${var.tfc_organization}:project:${coalesce(b.project, var.tfc_project)}:workspace:${ws}:run_phase:${phase}"
      ]
    }
  }

  # Trust policy documents (IAM JSON objects) per binding and phase.
  trust_policies = {
    for k, b in var.account_bindings : k => {
      for phase in ["plan", "apply"] : phase => {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "TfcWorkloadIdentity${title(phase)}"
          Effect    = "Allow"
          Principal = { Federated = { Ref = "TfcOidcProvider" } }
          Action    = "sts:AssumeRoleWithWebIdentity"
          # Built with for-expressions instead of a ternary so the two shapes
          # (StringEquals-only vs StringEquals + StringLike) need no type unification.
          Condition = merge(
            {
              StringEquals = merge(
                { (local.aud_key) = "aws.workload.identity" },
                { for _ in(var.allow_workspace_wildcards ? [] : [1]) : (local.sub_key) => local.subjects[k][phase] }
              )
            },
            { for _ in(var.allow_workspace_wildcards ? [1] : []) : "StringLike" => { (local.sub_key) = local.subjects[k][phase] } }
          )
        }]
      }
    }
  }

  oidc_provider = {
    TfcOidcProvider = {
      Type = "AWS::IAM::OIDCProvider"
      Properties = merge(
        {
          Url          = "https://${var.tfc_hostname}"
          ClientIdList = ["aws.workload.identity"]
        },
        { for _ in(length(var.oidc_thumbprints) > 0 ? [1] : []) : "ThumbprintList" => var.oidc_thumbprints }
      )
    }
  }

  role_resources = merge([
    for k, b in var.account_bindings : {
      "TfcPlanRole${local.logical_suffix[k]}" = {
        Type      = "AWS::IAM::Role"
        Condition = "Is${local.logical_suffix[k]}"
        Properties = {
          RoleName                 = var.plan_role_name
          Description              = "Terraform Cloud PLAN phase (read-only) for ${k}"
          AssumeRolePolicyDocument = local.trust_policies[k]["plan"]
          ManagedPolicyArns        = var.plan_role_policy_arns
          MaxSessionDuration       = var.max_session_duration
        }
      }
      "TfcApplyRole${local.logical_suffix[k]}" = {
        Type      = "AWS::IAM::Role"
        Condition = "Is${local.logical_suffix[k]}"
        Properties = {
          RoleName                 = var.apply_role_name
          Description              = "Terraform Cloud APPLY phase for ${k}"
          AssumeRolePolicyDocument = local.trust_policies[k]["apply"]
          ManagedPolicyArns        = var.apply_role_policy_arns
          MaxSessionDuration       = var.max_session_duration
        }
      }
    }
  ]...)

  conditions = {
    for k, b in var.account_bindings : "Is${local.logical_suffix[k]}" => {
      "Fn::Equals" = [{ Ref = "AWS::AccountId" }, b.account_id]
    }
  }

  template = merge(
    {
      AWSTemplateFormatVersion = "2010-09-09"
      Description              = "Terraform Cloud OIDC workload-identity baseline (managed by Terraform: modules/aws/iam/tfc-oidc-baseline)"
      Resources                = merge(local.oidc_provider, local.role_resources)
      Outputs = {
        OidcProviderArn = { Value = { Ref = "TfcOidcProvider" } }
      }
    },
    # CloudFormation rejects an empty Conditions section.
    { for _ in(length(local.conditions) > 0 ? [1] : []) : "Conditions" => local.conditions }
  )

  template_body = jsonencode(local.template)
}

resource "aws_cloudformation_stack_set" "this" {
  name             = var.stack_set_name
  description      = "Terraform Cloud OIDC provider + per-workspace plan/apply roles for member accounts."
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.template_body
  tags             = var.tags

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
    region_concurrency_type = "SEQUENTIAL"
  }

  lifecycle {
    # Known provider behaviour: AWS populates administration_role_arn on
    # SERVICE_MANAGED stack sets, which otherwise shows as perpetual drift.
    ignore_changes = [administration_role_arn]

    precondition {
      # Inline template_body limit is 51,200 bytes; beyond that a template_url
      # (S3) would be required.
      condition     = length(local.template_body) <= 51200
      error_message = "The generated StackSet template exceeds CloudFormation's 51,200-byte inline limit — reduce account_bindings or split the baseline."
    }
  }
}

# One stack instance per targeted OU, keyed by stable OU name so adding an OU
# never replaces (and thereby deletes) the instances for the existing OUs.
resource "aws_cloudformation_stack_set_instance" "this" {
  for_each = var.target_ou_ids

  stack_set_name            = aws_cloudformation_stack_set.this.name
  call_as                   = var.call_as
  stack_set_instance_region = var.stack_set_instance_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [each.value]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}
