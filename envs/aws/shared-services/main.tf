# Phase-2 shared-services root. Reads the phase-1 aws-organization root's remote
# state (credential-free config — the actual read happens with cloud creds at
# plan time) and composes the aws-shared-services stage: the org's
# account-agnostic shared platform services (ACM Private CA, Secrets Manager
# baseline) in the shared services account. It is a CONSUMER of the organization
# cross-root contract (organization_id, management_account_id, account_role_arns).
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
    organization_root_id  = try(local.org_remote.organization_root_id, null)
    management_account_id = local.org_remote.management_account_id
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
  # Org ARN for RAM org-wide sharing of the Private CA, built from existing
  # organization outputs (management account id + org id) so no extra
  # remote-state dependency is needed just to obtain the ARN.
  org_arn = "arn:${local.partition}:organizations::${local.org.management_account_id}:organization/${local.org.organization_id}"
}

module "aws_shared_services" {
  source = "../../../modules/aws/stages/shared-services"

  org_id  = local.org.organization_id
  org_arn = local.org_arn

  # ACM Private CA — org-shared internal certificate authority.
  enable_private_ca = var.enable_private_ca
  ca_common_name    = var.ca_common_name

  # Secrets Manager baseline — org-scoped secrets.
  enable_secrets_baseline = var.enable_secrets_baseline
  secrets                 = var.secrets
  secrets_kms_key_id      = var.secrets_kms_key_id
}
