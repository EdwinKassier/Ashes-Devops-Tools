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
  #     untag protected KMS keys, change a protected key's policy). A pipeline
  #     compromise cannot perform these — in particular it cannot rewrite a
  #     protected key policy to grant itself kms:Decrypt. Consequence: Terraform
  #     key-policy changes to protected keys require a break-glass apply (the
  #     aws/data/kms-key module sets the policy at CreateKey, so creation is
  #     unaffected).
  #     Trade-off: tearing down one of these services must go through break-glass.
  #     For this to work in member accounts a role with the break-glass name
  #     must exist there (e.g. deployed by StackSet).
  #   * privileged_arns — pipeline roles + break-glass. Reconfiguration actions
  #     that routine Terraform legitimately performs in member accounts (Config
  #     recorders in workload accounts, GuardDuty/CloudTrail settings in the
  #     security-tooling account, flow-log replacement, log-archive Object Lock).
  #     Local member-account admins are denied.
  #
  # Privileged-role IAM tampering (create/update/delete/attach on the protected
  # role names) uses its OWN two tiers — the pipeline is never exempt, so a
  # compromised member tfc-apply can neither squat the break-glass name
  # (CreateRole + inherit every break-glass exemption) nor rewrite the trust of
  # OrganizationAccountAccessRole and assume it:
  #   * DenyPrivilegedRoleTampering — OAAR, stacksets-exec-* and any other
  #     pipeline_role_names that no StackSet manages. Exempt: break-glass only.
  #   * DenyStackSetRoleTampering — the StackSet-managed roles (tfc-plan /
  #     tfc-apply from tfc-oidc-baseline, and the member break-glass role the
  #     sibling StackSet deploys). Exempt: break-glass plus the StackSet
  #     execution role (stacksets-exec-*), which must create/update exactly
  #     these roles. stacksets-exec-* is only assumable by the management-account
  #     StackSets service, and is itself break-glass-only protected above.
  break_glass_role_names = length(var.break_glass_role_names) > 0 ? var.break_glass_role_names : [
    regex("role/(.+)$", var.break_glass_role_arn)[0]
  ]
  break_glass_principal_arns = [for n in local.break_glass_role_names : "arn:aws:iam::*:role/${n}"]
  privileged_principal_arns = distinct(concat(
    [for n in var.pipeline_role_names : "arn:aws:iam::*:role/${n}"],
    local.break_glass_principal_arns,
  ))

  stackset_role_arns = distinct(concat(
    [for n in var.stackset_managed_role_names : "arn:aws:iam::*:role/${n}"],
    local.break_glass_principal_arns,
  ))
  admin_role_arns = [
    for a in distinct(concat(
      [for n in var.pipeline_role_names : "arn:aws:iam::*:role/${n}"],
      [for n in var.stackset_execution_role_names : "arn:aws:iam::*:role/${n}"],
    )) : a if !contains(local.stackset_role_arns, a)
  ]
  stackset_exempt_arns = distinct(concat(
    local.break_glass_principal_arns,
    [for n in var.stackset_execution_role_names : "arn:aws:iam::*:role/${n}"],
  ))
  role_tamper_actions = [
    "iam:CreateRole",
    "iam:DeleteRole",
    "iam:UpdateRole",
    "iam:UpdateAssumeRolePolicy",
    "iam:AttachRolePolicy",
    "iam:DetachRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:PutRolePermissionsBoundary",
    "iam:DeleteRolePermissionsBoundary",
  ]

  default_policies = {
    # Minified (jsonencode(jsondecode(...))) so the 5,120-character SCP size
    # quota is spent on content, not indentation.
    scp-deny-tamper = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-deny-tamper.json.tftpl", {
        break_glass_arns        = jsonencode(local.break_glass_principal_arns)
        privileged_arns         = jsonencode(local.privileged_principal_arns)
        admin_role_arns         = local.admin_role_arns
        stackset_role_arns      = local.stackset_role_arns
        stackset_exempt_arns    = local.stackset_exempt_arns
        role_tamper_actions     = jsonencode(local.role_tamper_actions)
        log_archive_bucket_name = var.log_archive_bucket_name
        kms_protection_tag_key  = var.kms_protection_tag_key
        # GuardDuty / CloudTrail / Security Hub settings are managed centrally
        # (delegated admin). Outside those accounts even the pipeline is denied,
        # so a compromised workload tfc-apply cannot add a suppression filter or
        # trim trail event selectors to blind detection.
        central_detection_account_ids = var.central_detection_account_ids
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
    # Baseline also carries two org-wide break-glass-only denies (kept here so
    # deny-tamper stays under the 5,120-char quota and no extra SCP attachment
    # is needed — a target allows at most 5 SCPs incl. FullAWSAccess):
    #   * DenyIamUserCredentials — no IAM users / access keys / console
    #     passwords (no module in this repo creates IAM users; identities come
    #     from Identity Center and OIDC federation).
    #   * DenyDataPerimeterTagTampering — the RCP's dp:exclude:* resource-tag
    #     escape hatches can only be set or removed by break-glass, so a member
    #     principal cannot self-exempt a resource from the data perimeter.
    scp-baseline = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-baseline.json.tftpl", {
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
        break_glass_arns       = jsonencode(local.break_glass_principal_arns)
      })))
    }
    rcp-data-perimeter = {
      type = "RESOURCE_CONTROL_POLICY"
      # Follows the AWS data-perimeter-policy-examples RCP: explicit STS action
      # list (AssumeRoleWithWebIdentity / AssumeRoleWithSAML are deliberately
      # excluded so OIDC/SAML federation, e.g. TFC dynamic credentials, still
      # works), a Null aws:SourceAccount guard on the confused-deputy statement
      # (service-principal calls without source context — EC2/Lambda/ECS role
      # assumption — are not denied), and dp:exclude:* resource-tag escape hatches.
      # Web-identity federation is instead pinned per issuer (federation_tenant_pins):
      # a token from app.terraform.io / GitHub is accepted only from YOUR TFC org /
      # GitHub owners, so an apply identity cannot mint a role trusting another
      # tenant on the same issuer (a persistence backdoor no boundary can see).
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/rcp-data-perimeter.json.tftpl", {
        org_id              = var.org_id
        trusted_account_ids = var.data_perimeter_trusted_account_ids
        tfc_hostname        = var.federation_tenant_pins.tfc_hostname
        tfc_organization    = var.federation_tenant_pins.tfc_organization
        github_owners       = var.federation_tenant_pins.github_owners
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
