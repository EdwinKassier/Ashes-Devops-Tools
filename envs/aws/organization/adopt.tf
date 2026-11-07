# ── Brownfield adoption: import an existing AWS Organization ────────────────
# Most enterprises already have an organization, and often OUs and accounts.
# Without these imports the first apply fails with AlreadyInOrganizationException
# (and DuplicateOrganizationalUnitException / duplicate account emails).
# Declare what exists in adopt_existing (or aws.adopt in config/landing-zone.yaml)
# and the first plan imports it instead of creating it. The plan then shows any
# drift between the live resources and this repo's settings; review it.
# Runbook: docs/runbooks/aws-brownfield-adoption.md (incl. Control Tower).

import {
  for_each = local.adopt_existing.organization_id == null ? toset([]) : toset([local.adopt_existing.organization_id])
  to       = module.aws_organization.module.organization.aws_organizations_organization.this
  id       = each.value
}

# Top-level OUs, keyed by OU name (e.g. "Security").
import {
  for_each = { for k, id in local.adopt_existing.ou_ids : k => id if !strcontains(k, "/") }
  to       = module.aws_organization.module.organization.aws_organizations_organizational_unit.top[each.key]
  id       = each.value
}

# Child OUs, keyed "<parent>/<name>" (e.g. "Workloads/Prod").
import {
  for_each = { for k, id in local.adopt_existing.ou_ids : k => id if strcontains(k, "/") }
  to       = module.aws_organization.module.organization.aws_organizations_organizational_unit.child[each.key]
  id       = each.value
}

# Member accounts, keyed by the account key in accounts / workload_accounts.
import {
  for_each = local.adopt_existing.account_ids
  to       = module.aws_organization.module.account[each.key].aws_organizations_account.this
  id       = each.value
}

# The CloudTrail delegated admin. aws-security registered cloudtrail.amazonaws.com
# through the generic Organizations API before enable_cloudtrail_delegated_admin;
# CloudTrail rejects a second registration (AccountRegisteredException), so an
# existing estate imports it. Greenfield leaves the ID unset and it is created.
import {
  for_each = local.enable_cloudtrail_delegated_admin && local.adopt_existing.cloudtrail_delegated_admin_account_id != null ? toset([local.adopt_existing.cloudtrail_delegated_admin_account_id]) : toset([])
  to       = module.aws_organization.aws_cloudtrail_organization_delegated_admin_account.this[0]
  id       = each.value
}
