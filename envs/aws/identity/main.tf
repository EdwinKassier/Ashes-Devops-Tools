# Phase-2 identity root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws/iam-identity-center module: permission sets and
# account assignments managed WITHIN the already-enabled Identity Center
# instance, administered from the shared-services delegated-admin account. It is
# a CONSUMER of the organization cross-root contract (account_role_arns for the
# provider, account_ids for wiring assignments to concrete member accounts).
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
    organization_id       = try(local.org_remote.organization_id, null)
    organization_root_id  = try(local.org_remote.organization_root_id, null)
    management_account_id = try(local.org_remote.management_account_id, null)
    ou_ids                = try(tomap(local.org_remote.ou_ids), {})
    account_ids           = tomap(local.org_remote.account_ids)
    account_role_arns     = try(tomap(local.org_remote.account_role_arns), {})
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

locals {
  # Explicit assignments pass straight through (existing keys are unchanged).
  # aws.identity.groups (or var.identity_groups) adds name-based assignments:
  # one per group x permission set x account key, keyed
  # "<group>/<permission set>/<account key>"; the module resolves the group by
  # display name and the account key through the org contract account_ids.
  identity_groups = coalesce(var.identity_groups, local.cfg.identity_groups, {})
  group_assignments = merge(flatten([
    for g, entries in local.identity_groups : [
      for e in entries : {
        for a in e.accounts : "${g}/${e.permission_set}/${a}" => {
          permission_set     = e.permission_set
          group_display_name = g
          account_key        = a
        }
      }
    ]
  ])...)
  assignments = merge(var.assignments, local.group_assignments)
}

# Production guard: broad write permission sets (production_restricted_permission_sets,
# default Developer) are refused in production workload accounts. An
# assignment names its account by key (group-derived and explicit) or by ID
# (explicit only); both forms are checked.
locals {
  production_account_keys = var.production_account_keys != null ? var.production_account_keys : local.cfg.production_account_keys
  production_account_ids  = compact([for k in local.production_account_keys : lookup(local.org.account_ids, k, "")])
  restricted_production_assignments = sort([
    for key, a in local.assignments : key
    if contains(var.production_restricted_permission_sets, a.permission_set) && (
      contains(local.production_account_keys, coalesce(try(a.account_key, null), "-")) ||
      contains(local.production_account_ids, coalesce(try(a.account_id, null), "-"))
    )
  ])
}

resource "terraform_data" "production_assignment_guard" {
  input = local.restricted_production_assignments

  lifecycle {
    precondition {
      condition     = length(local.restricted_production_assignments) == 0
      error_message = "These assignments give a restricted permission set (${join(", ", var.production_restricted_permission_sets)}) in a production account: ${join(", ", local.restricted_production_assignments)}. Use a read-only or scoped set there, with time-boxed elevation through the identity provider (docs/adr/0011-temporary-elevated-access.md), or change production_restricted_permission_sets and record the reason."
    }
  }
}

module "iam_identity_center" {
  source = "../../../modules/aws/iam/iam-identity-center"

  permission_sets = var.permission_sets
  assignments     = local.assignments
  account_ids     = local.org.account_ids

  enable_abac     = var.enable_abac
  abac_attributes = var.abac_attributes
}
