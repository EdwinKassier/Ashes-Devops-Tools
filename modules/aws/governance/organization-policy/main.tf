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
  break_glass_principal_arns = [for n in local.break_glass_role_names : "arn:${var.partition}:iam::*:role/${n}"]
  privileged_principal_arns = distinct(concat(
    [for n in var.pipeline_role_names : "arn:${var.partition}:iam::*:role/${n}"],
    local.break_glass_principal_arns,
  ))

  stackset_role_arns = distinct(concat(
    [for n in var.stackset_managed_role_names : "arn:${var.partition}:iam::*:role/${n}"],
    local.break_glass_principal_arns,
  ))
  admin_role_arns = [
    for a in distinct(concat(
      [for n in var.pipeline_role_names : "arn:${var.partition}:iam::*:role/${n}"],
      [for n in var.stackset_execution_role_names : "arn:${var.partition}:iam::*:role/${n}"],
    )) : a if !contains(local.stackset_role_arns, a)
  ]
  stackset_exempt_arns = distinct(concat(
    local.break_glass_principal_arns,
    [for n in var.stackset_execution_role_names : "arn:${var.partition}:iam::*:role/${n}"],
  ))
  # Recorder SCP (enable_config_recorder_scp): once the org-wide recorder
  # StackSet owns every member recorder, only the StackSet execution role,
  # break-glass and the listed account-qualified pipeline roles (security
  # tooling's tfc-apply, which manages the aggregator recorder) may change
  # recorders. Role ARNs only, never a whole account.
  config_recorder_exempt_arns = distinct(concat(
    [for n in var.stackset_execution_role_names : "arn:${var.partition}:iam::*:role/${n}"],
    local.break_glass_principal_arns,
    var.config_recorder_pipeline_role_arns,
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
    # Minified (jsonencode(jsondecode(...))) so the 10,240-character SCP size
    # quota is spent on content, not indentation.
    scp-deny-tamper = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-deny-tamper.json.tftpl", {
        partition               = var.partition
        break_glass_arns        = jsonencode(local.break_glass_principal_arns)
        privileged_arns         = jsonencode(local.privileged_principal_arns)
        admin_role_arns         = local.admin_role_arns
        stackset_role_arns      = local.stackset_role_arns
        stackset_exempt_arns    = local.stackset_exempt_arns
        role_tamper_actions     = jsonencode(local.role_tamper_actions)
        log_archive_bucket_name = var.log_archive_bucket_name
        kms_protection_tag_key  = var.kms_protection_tag_key
        # Recorder actions: DenyWeakenSecurityServices (pipeline-wide exemption)
        # until the migration, then DenyConfigRecorderChanges.
        enable_config_recorder_scp  = var.enable_config_recorder_scp
        config_recorder_exempt_arns = jsonencode(local.config_recorder_exempt_arns)
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
        allowed_regions = jsonencode(var.allowed_regions)
        # CloudFront certificates (ACM) and their keys must live in us-east-1,
        # so edge deployments (enable_edge) work without allowing the region.
        allowed_regions_with_us_east_1 = jsonencode(distinct(concat(var.allowed_regions, ["us-east-1"])))
        # Break-glass is the only exemption. The run role is not: global-service
        # calls are in the template's NotAction, so it needs no carve-out.
        break_glass_role_arn = var.break_glass_role_arn
      })
    }
    # Suspended OU: deny everything except break-glass and the StackSet execution
    # role (so the org-wide StackSets can still reconcile the account). SCPs never
    # touch the management account, so this cannot lock out the pipeline there.
    scp-suspended-deny-all = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-deny-all.json.tftpl", {
        exempt_arns = jsonencode(local.stackset_exempt_arns)
      })))
    }
    # Sandbox OU: small instance types only, no Direct Connect, no VPC peering,
    # no Organizations API. Break-glass is exempt.
    scp-sandbox-guard = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-sandbox-guard.json.tftpl", {
        partition              = var.partition
        allowed_instance_types = jsonencode(var.sandbox_allowed_instance_types)
        break_glass_arns       = jsonencode(local.break_glass_principal_arns)
      })))
    }
    # Baseline also carries two org-wide break-glass-only denies (kept here so
    # deny-tamper stays well under the 10,240-char quota and no extra SCP
    # attachment is needed — a target allows at most 10 SCPs incl. FullAWSAccess):
    #   * DenyIamUserCredentials — no IAM users / access keys / console
    #     passwords (no module in this repo creates IAM users; identities come
    #     from Identity Center and OIDC federation).
    #   * DenyDataPerimeterTagTampering — the RCP's dp:exclude:* resource-tag
    #     escape hatches can only be set or removed by break-glass, so a member
    #     principal cannot self-exempt a resource from the data perimeter.
    scp-baseline = {
      type = "SERVICE_CONTROL_POLICY"
      content = jsonencode(jsondecode(templatefile("${path.module}/policies/scp-baseline.json.tftpl", {
        partition              = var.partition
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
        break_glass_arns       = jsonencode(local.break_glass_principal_arns)
        # New trust anchors (OIDC / SAML providers) are registered only by
        # break-glass and the StackSet execution role (tfc-oidc-baseline owns the
        # TFC and GitHub providers). Everyone else, the pipeline and member
        # admins included, is denied: an attacker-owned issuer plus a role that
        # trusts it is an MFA-less, rotation-proof door.
        idp_admin_arns = jsonencode(local.stackset_exempt_arns)
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
        github_owner_ids    = var.federation_tenant_pins.github_owner_ids
        allowed_builtin     = var.federation_tenant_pins.allowed_builtin_providers
      })))
    }
    declarative-ec2 = {
      type = "DECLARATIVE_POLICY_EC2"
      content = templatefile("${path.module}/policies/declarative-ec2.json", {
        vpc_bpa_exclusions_allowed = var.allow_vpc_bpa_exclusions ? "enabled" : "disabled"
      })
    }
    # Org-wide EC2 baseline WITHOUT VPC Block Public Access: IMDSv2, no public
    # snapshot / AMI sharing, no serial console. Attached at the root so the
    # Security and Infrastructure accounts get it too; declarative-ec2 (with
    # VPC BPA) stays on the Workloads OU, where public ingress goes through
    # the edge layer only.
    declarative-ec2-baseline = {
      type    = "DECLARATIVE_POLICY_EC2"
      content = file("${path.module}/policies/declarative-ec2-baseline.json")
    }
    # Opt every account out of AWS AI services using its content to improve
    # those services (data-residency / IP hygiene default).
    aiservices-opt-out = {
      type    = "AISERVICES_OPT_OUT_POLICY"
      content = file("${path.module}/policies/aiservices-opt-out.json")
    }
    tag-policy = {
      type    = "TAG_POLICY"
      content = templatefile("${path.module}/policies/tag-policy.json", {})
    }
    backup-policy = {
      type = "BACKUP_POLICY"
      content = templatefile("${path.module}/policies/backup-policy.json", {
        partition      = var.partition
        default_region = var.default_region
      })
    }
  }

  # policies (non-empty) replaces the whole set (legacy). Otherwise the built-in
  # set minus disabled_policies, with policy_overrides merged over it: replace a
  # built-in policy's content, or add your own, without forking the module.
  effective_policies = length(var.policies) > 0 ? var.policies : merge(
    { for k, p in local.default_policies : k => p if !contains(var.disabled_policies, k) },
    var.policy_overrides,
  )
}

resource "aws_organizations_policy" "policy" {
  for_each = local.effective_policies
  name     = each.key
  type     = each.value.type
  content  = each.value.content
  tags     = var.tags
}

resource "aws_organizations_policy_attachment" "attach" {
  for_each  = var.attachments
  policy_id = aws_organizations_policy.policy[each.value.policy_key].id
  target_id = each.value.target_id
}

# The core guardrails are the landing zone's security floor. Replacing or
# dropping one is allowed (escape hatch), but never silently.
locals {
  core_guardrails     = ["scp-deny-tamper", "scp-baseline", "rcp-data-perimeter"]
  weakened_guardrails = sort([for k in local.core_guardrails : k if contains(var.disabled_policies, k) || contains(keys(var.policy_overrides), k) || (length(var.policies) > 0 && !contains(keys(var.policies), k))])
}

check "core_guardrails_not_weakened" {
  assert {
    condition     = length(local.weakened_guardrails) == 0
    error_message = "Core guardrail policies are replaced or removed: ${join(", ", local.weakened_guardrails)}. The deny-tamper SCP, root/IAM-user baseline SCP and RCP data perimeter are the security floor; make sure the replacement keeps their protections and record the exception."
  }
}
