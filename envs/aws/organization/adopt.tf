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
