# Delegated-administrator registration for the SRA landing zone.
#
# Registers delegated administrators for organization services that do NOT have
# a dedicated `*_organization_admin_account` / `*_delegated_admin_account`
# resource of their own. Those services (GuardDuty, Macie, Inspector, Detective,
# Security Hub) are registered elsewhere through their dedicated resources; doing
# it here as well would double-register and produce an apply error.
#
# This module runs from the organization MANAGEMENT account: the default
# provider IS the management account, so no aliased provider is required
# (aws_organizations_delegated_administrator must be created from the management
# account).
#
# The effective registration map is either the explicit `registrations` input
# (service principal -> delegated-admin account ID) or, when that is left empty,
# a convenience default assembled from `security_tooling_account_id` and
# `identity_account_id`.

locals {
  # Services with no dedicated admin resource, delegated to the Security Tooling
  # account, plus IAM Identity Center (sso) which is delegated to the Identity
  # account.
  default_registrations = {
    "access-analyzer.amazonaws.com"          = var.security_tooling_account_id
    "backup.amazonaws.com"                   = var.security_tooling_account_id
    "config.amazonaws.com"                   = var.security_tooling_account_id
    "config-multiaccountsetup.amazonaws.com" = var.security_tooling_account_id
    "cloudtrail.amazonaws.com"               = var.security_tooling_account_id
    "fms.amazonaws.com"                      = var.security_tooling_account_id
    "ssm.amazonaws.com"                      = var.security_tooling_account_id
    "resource-explorer-2.amazonaws.com"      = var.security_tooling_account_id
    "securitylake.amazonaws.com"             = var.security_tooling_account_id
  }
  # IAM Identity Center delegation is identity control over every account.
  # Off by default here: aws-organization registers it as the phase-0 role
  # (identity_center_admin_account_key), so the least-privilege aws-security
  # management role never needs sso.amazonaws.com.
  sso_registration = var.register_identity_center_admin ? { "sso.amazonaws.com" = var.identity_account_id } : {}

  effective_registrations = length(var.registrations) > 0 ? var.registrations : merge(local.default_registrations, local.sso_registration)
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each          = local.effective_registrations
  account_id        = each.value
  service_principal = each.key
}
