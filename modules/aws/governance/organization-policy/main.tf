# AWS Organizations guardrail policies for the SRA landing zone.
#
# Renders a set of organization policies from templated JSON files and attaches
# them to OU/account targets. Covers all five Organizations policy types:
#   - SERVICE_CONTROL_POLICY (SCP)   — deny-tamper, region-restriction, baseline
#   - RESOURCE_CONTROL_POLICY (RCP)  — two-statement data perimeter + TLS
#   - DECLARATIVE_POLICY_EC2         — IMDSv2 + public-access blocks (@@assign)
#   - TAG_POLICY                     — required cost/ownership tag keys
#   - BACKUP_POLICY                  — a sensible daily backup plan
#
# The policy content strings are computed here in locals (a variable `default`
# cannot reference var.* or path.module, both of which the templatefile renders
# need). Callers can override the whole set by passing a non-empty `policies`.
#
# FullAWSAccess / RCPFullAWSAccess are AWS-managed and deliberately never
# managed here.

locals {
  # scp-deny-tamper carve-outs are ROLE-NAME patterns that match the role in ANY
  # member account (arn:aws:iam::*:role/<name>), not account-qualified ARNs.
  # SCPs never apply to the management account, so a carve-out (or a protected
  # resource) keyed on a management-account ARN is inert: it can neither exempt a
  # member-account session nor protect anything. The previous version protected
  # and exempted management-account roles only — that statement has been replaced
  # by DenyPrivilegedRoleTampering, which protects the member-account pipeline
  # roles, OrganizationAccountAccessRole and the break-glass role.
  #
  # Two exemption tiers:
  #   * break_glass_arns — break-glass only. Destructive actions (leave org,
  #     stop/delete CloudTrail, delete GuardDuty detector/members, disable
  #     Security Hub / Macie / Inspector, delete Access Analyzer, destroy or
  #     untag protected KMS keys). A pipeline compromise cannot perform these.
  #     Trade-off: tearing down one of these services must go through break-glass.
  #     For this to work in member accounts a role with the break-glass name
  #     must exist there (e.g. deployed by StackSet).
  #   * privileged_arns — pipeline roles + break-glass. Reconfiguration actions
  #     that routine Terraform legitimately performs in member accounts (Config
  #     recorders in workload accounts, GuardDuty/CloudTrail settings in the
  #     security-tooling account, flow-log replacement, protected key policies).
  #     Local member-account admins are denied.
  break_glass_role_names = length(var.break_glass_role_names) > 0 ? var.break_glass_role_names : [
    regex("role/(.+)$", var.break_glass_role_arn)[0]
  ]
  break_glass_principal_arns = [for n in local.break_glass_role_names : "arn:aws:iam::*:role/${n}"]
  privileged_principal_arns = distinct(concat(
    [for n in var.pipeline_role_names : "arn:aws:iam::*:role/${n}"],
    local.break_glass_principal_arns,
  ))

  default_policies = {
    # Minified (jsonencode(jsondecode(...))) so the 5,120-character SCP size
    # quota is spent on content, not indentation.
    scp-deny-tamper = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-deny-tamper.json.tftpl", {
        break_glass_arns        = jsonencode(local.break_glass_principal_arns)
        privileged_arns         = jsonencode(local.privileged_principal_arns)
        log_archive_bucket_name = var.log_archive_bucket_name
        kms_protection_tag_key  = var.kms_protection_tag_key
      })))
    }
    scp-region-restriction = {
      type = "SERVICE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/scp-region-restriction.json.tftpl", {
        allowed_regions        = jsonencode(var.allowed_regions)
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
      })
    }
    scp-baseline = {
      type = "SERVICE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/scp-baseline.json", {
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
      })
    }
    rcp-data-perimeter = {
      type = "RESOURCE_CONTROL_POLICY"
      # Follows the AWS data-perimeter-policy-examples RCP: explicit STS action
      # list (AssumeRoleWithWebIdentity / AssumeRoleWithSAML are deliberately
      # excluded so OIDC/SAML federation, e.g. TFC dynamic credentials, still
      # works), a Null aws:SourceAccount guard on the confused-deputy statement
      # (service-principal calls without source context — EC2/Lambda/ECS role
      # assumption — are not denied), and dp:exclude:* resource-tag escape hatches.
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/rcp-data-perimeter.json.tftpl", {
        org_id              = var.org_id
        trusted_account_ids = var.data_perimeter_trusted_account_ids
      })))
    }
    declarative-ec2 = {
      type = "DECLARATIVE_POLICY_EC2"
      content = templatefile("${path.module}/policies/declarative-ec2.json", {
        vpc_bpa_exclusions_allowed = var.allow_vpc_bpa_exclusions ? "enabled" : "disabled"
      })
    }
    tag-policy = {
      type    = "TAG_POLICY"
      content = templatefile("${path.module}/policies/tag-policy.json", {})
    }
    backup-policy = {
      type = "BACKUP_POLICY"
      content = templatefile("${path.module}/policies/backup-policy.json", {
        default_region = var.default_region
      })
    }
  }

  effective_policies = length(var.policies) > 0 ? var.policies : local.default_policies
}

resource "aws_organizations_policy" "policy" {
  for_each = local.effective_policies
  name     = each.key
  type     = each.value.type
  content  = each.value.content
}

resource "aws_organizations_policy_attachment" "attach" {
  for_each  = var.attachments
  policy_id = aws_organizations_policy.policy[each.value.policy_key].id
  target_id = each.value.target_id
}
