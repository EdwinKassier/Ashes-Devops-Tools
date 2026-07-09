# Phase-2 identity root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws/iam-identity-center module: permission sets and
# account assignments managed WITHIN the already-enabled Identity Center
# instance, administered from the shared-services delegated-admin account. It is
# a CONSUMER of the organization cross-root contract (account_role_arns for the
# provider, account_ids for wiring assignments to concrete member accounts).
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # Assignments passed straight through. Callers may set account_id directly, or
  # reference a member account by name from the org cross-root contract
  # (data.terraform_remote_state.aws_organization.outputs.account_ids), e.g. in
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
  source = "../../modules/aws/iam-identity-center"

  permission_sets = var.permission_sets
  assignments     = local.assignments

  enable_abac     = var.enable_abac
  abac_attributes = var.abac_attributes
}
