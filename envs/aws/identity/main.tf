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
  # The organization contract this root consumes, whichever source supplied it
  # (the remote state is projected onto the contract's fields so both branches
  # share one type).
  org = local.read_organization ? {
    account_ids = tomap(data.terraform_remote_state.aws_organization[0].outputs.account_ids)
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

module "iam_identity_center" {
  source = "../../../modules/aws/iam/iam-identity-center"

  permission_sets = var.permission_sets
  assignments     = local.assignments
  account_ids     = local.org.account_ids

  enable_abac     = var.enable_abac
  abac_attributes = var.abac_attributes
}
