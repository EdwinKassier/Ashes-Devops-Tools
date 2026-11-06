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
  # The organization contract this root consumes, whichever source supplied it
  # (the remote state is projected onto the contract's fields so both branches
  # share one type).
  org = local.read_organization ? {
    organization_id       = data.terraform_remote_state.aws_organization[0].outputs.organization_id
    management_account_id = data.terraform_remote_state.aws_organization[0].outputs.management_account_id
    account_ids           = tomap(data.terraform_remote_state.aws_organization[0].outputs.account_ids)
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
  org_arn = "arn:aws:organizations::${local.org.management_account_id}:organization/${local.org.organization_id}"
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
