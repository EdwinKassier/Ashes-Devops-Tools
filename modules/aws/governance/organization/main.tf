# AWS Organizations control plane for the SRA landing zone.
#
# Creates the organization with feature_set = "ALL" (required for SCPs, RCPs,
# declarative/tag/backup policies) and builds the SRA OU tree: a set of
# top-level OUs plus optional child OUs under them. Trusted service access is
# enabled for the full SRA security service set so delegated administration
# (GuardDuty, Security Hub, Config, etc.) can be wired up downstream.
#
# feature_set = "ALL" is deliberate: starting an org at CONSOLIDATED_BILLING and
# later upgrading to ALL produces a perpetual diff, so we pin ALL from creation.

resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  enabled_policy_types          = var.enabled_policy_types
  aws_service_access_principals = var.aws_service_access_principals
}

resource "aws_organizations_organizational_unit" "top" {
  for_each  = toset(var.top_level_ous)
  name      = each.key
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "child" {
  for_each  = { for c in var.child_ous : "${c.parent}/${c.name}" => c }
  name      = each.value.name
  parent_id = aws_organizations_organizational_unit.top[each.value.parent].id
}
