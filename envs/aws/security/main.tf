# Phase-2 security root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan time)
# and composes the aws-security stage: the SRA security baseline across the
# management, security-tooling, log-archive and forensics accounts. It is a
# CONSUMER of the cross-root contract (organization_id, organization_root_id,
# account_ids, account_role_arns, management_account_id) and re-exports the
# security cross-root contract for downstream roots.
# Stage contract override (FAST-style): var.organization_contract (or
# aws.contracts.organization in config/landing-zone.yaml) replaces this read —
# count = 0 — so the root can plan without the aws-organization workspace.
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  read_organization     = local.organization_contract == null
  # The upstream contract output. A producer state from before the contract
  # output existed (N-1, not yet re-applied) exposes the same keys as
  # individual outputs, so the read falls back to them; that fallback goes at
  # v1.0 with the individual outputs (UPGRADING.md).
  org_remote = local.read_organization ? try(data.terraform_remote_state.aws_organization[0].outputs.contract, data.terraform_remote_state.aws_organization[0].outputs) : null
  # The organization contract, whichever source supplied it, as one type (the
  # variable's). Fields this root needs are read strictly (a missing key fails
  # the plan); the rest default.
  org = local.read_organization ? {
    organization_id       = local.org_remote.organization_id
    organization_root_id  = local.org_remote.organization_root_id
    management_account_id = local.org_remote.management_account_id
    ou_ids                = try(tomap(local.org_remote.ou_ids), {})
    account_ids           = tomap(local.org_remote.account_ids)
    account_role_arns     = tomap(local.org_remote.account_role_arns)
  } : local.organization_contract
}

data "terraform_remote_state" "aws_organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

module "aws_security" {
  source = "../../../modules/aws/stages/security"

  # The default provider authenticates as / into the management account, so it is
  # mapped to both aws and aws.management. The other three are aliased providers
  # assuming cross-account roles from the organization remote state.
  providers = {
    aws                  = aws
    aws.management       = aws
    aws.security_tooling = aws.security_tooling
    aws.log_archive      = aws.log_archive
    aws.forensics        = aws.forensics
  }

  org_id                      = local.org.organization_id
  org_root_id                 = local.org.organization_root_id
  management_account_id       = local.org.management_account_id
  security_tooling_account_id = local.org.account_ids["security_tooling"]
  log_archive_account_id      = local.org.account_ids["log_archive"]
  shared_services_account_id  = local.org.account_ids["shared_services"]
  forensics_account_id        = local.org.account_ids["forensics"]
  backup_account_id           = lookup(local.org.account_ids, "backup", null)

  aws_region = local.aws_region
  partition  = local.partition

  # Kept apart from the aws object: null (legacy) is a meaningful value here.
  key_policy_admin_role_name = var.key_policy_admin_role_name

  # Every tuning input: the aws section (config/landing-zone.yaml aws.* under
  # var.aws_overrides), plus the values this root derives from the profile,
  # notifications.emails and the management account.
  aws = merge(local.aws, {
    aws_enabled_regions      = local.aws_enabled_regions
    notification_subscribers = local.notification_subscribers
    # Cost toggles for the most expensive always-on security services follow
    # the profile unless set explicitly.
    enabled_security_services               = local.enabled_security_services
    enable_security_lake                    = local.enable_security_lake
    config_record_all_supported             = local.config_record_all_supported
    guardduty_enable_ebs_malware_protection = local.guardduty_enable_ebs_malware_protection
    # aws-organization creates the trail's CloudWatch delivery role
    # (create_org_trail_delivery_role), so this root needs no IAM writes in the
    # management account.
    cloudtrail_cloudwatch_role_arn = coalesce(try(local.aws.cloudtrail_cloudwatch_role_arn, null), "arn:${local.partition}:iam::${local.management_account_id}:role/org-trail-cloudwatch-delivery")
  })
}

# The dedicated least-privilege aws-security management role (tfc-management-
# roles) has no IAM write and is denied the break-glass role. The phase-0 roles
# tfc-mgmt-plan and tfc-mgmt-apply are denied editing OrganizationBreakGlass
# too (deny-self-tampering in templates/aws/bootstrap/phase0-management.yaml),
# so that role changes only through a human-run update of the phase-0 stack.
# create_break_glass can only create a role with another name, applied as
# tfc-mgmt-apply, which leaves a second break-glass role to keep in step.
check "break_glass_created_by_phase0_stack" {
  assert {
    condition     = !coalesce(try(local.aws.create_break_glass, null), false)
    error_message = "aws_overrides.create_break_glass = true: the dedicated tfc-mgmt-aws-security role cannot create or edit the management break-glass role (AccessDenied). Use the OrganizationBreakGlass role from templates/aws/bootstrap/phase0-management.yaml and keep aws_overrides.create_break_glass unset (false). That role changes only through a human-run update of the phase-0 stack: the phase-0 roles are denied editing it too."
  }
}

# ---------------------------------------------------------------------------
# CMP-6: security notifications must reach a real, staffed address.
# ---------------------------------------------------------------------------

locals {
  # The host of each subscriber endpoint: the domain of an email address, the
  # host of a URL, "" for an ARN or a phone number.
  subscriber_hosts = {
    for k, s in local.notification_subscribers : k => lower(try(
      regex("@([^@]+)$", s.endpoint)[0],
      regex("^[A-Za-z][A-Za-z0-9+.-]*://([^/:?#@]+)", s.endpoint)[0],
      ""
    ))
  }
  # Subscribers on a reserved, never-delivered domain (RFC 2606 / RFC 6761):
  # example.com/.net/.org and their subdomains, *.example, *.invalid,
  # *.localhost, *.test.
  placeholder_subscribers = sort([
    for k, h in local.subscriber_hosts : k
    if can(regex("(^|\\.)(example\\.(com|net|org)|example|invalid|localhost|test)$", h))
  ])
  # Production: org.profile = production, or any aws.workload_environments entry
  # with is_production: true.
  security_contact_required = local.profile == "production" || length(local.cfg.workload_production) > 0
}

resource "terraform_data" "security_contact_guard" {
  input = sort(keys(local.notification_subscribers))

  lifecycle {
    precondition {
      condition     = !local.security_contact_required || (length(local.notification_subscribers) > 0 && length(local.placeholder_subscribers) == 0)
      error_message = "Production security notifications have no real subscriber${length(local.placeholder_subscribers) > 0 ? " (placeholder domain: ${join(", ", local.placeholder_subscribers)})" : ""}. Set notifications.emails in config/landing-zone.yaml, or aws_overrides.notification_subscribers. Example, .invalid, .localhost and .test domains are rejected. Production means org.profile = production or an aws.workload_environments entry with is_production: true."
    }
  }
}

# Non-production: warn only.
check "security_contact_set" {
  assert {
    condition     = length(local.notification_subscribers) > 0 && length(local.placeholder_subscribers) == 0
    error_message = "No real security notification subscriber is set (notifications.emails or aws_overrides.notification_subscribers): GuardDuty, Security Hub and break-glass alerts will fire without notifying anyone."
  }
}
