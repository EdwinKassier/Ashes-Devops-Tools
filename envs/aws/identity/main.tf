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
  # Assignments passed straight through. Callers may set account_id directly, or
  # reference a member account by name from the org cross-root contract
  # (local.org.account_ids), e.g. in
  # tfvars:
  #
  #   assignments = {
  #     admins-shared-services = {
  #       permission_set = "AdministratorAccess"
  #       principal_type = "GROUP"
  #       principal_id   = "<identity-store-group-id>"
  #       account_id     = "<shared_services account id from account_ids>"
  #     }
  #   }
  #
  # The pass-through keeps the root generic. The account_ids map is exported
  # below as an output so operators can resolve names to ids.
  assignments = var.assignments
}

module "iam_identity_center" {
  source = "../../../modules/aws/iam/iam-identity-center"

  permission_sets = var.permission_sets
  assignments     = local.assignments

  enable_abac     = var.enable_abac
  abac_attributes = var.abac_attributes
}
