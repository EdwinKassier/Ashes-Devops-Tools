# Phase-2 shared-services root. Reads the phase-1 aws-organization root's remote
# state (credential-free config — the actual read happens with cloud creds at
# plan time) and composes the aws-shared-services stage: the org's
# account-agnostic shared platform services (ACM Private CA, Secrets Manager
# baseline) in the shared services account. It is a CONSUMER of the organization
# cross-root contract (organization_id, management_account_id, account_role_arns).
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # Org ARN for RAM org-wide sharing of the Private CA, built from existing
  # organization outputs (management account id + org id) so no extra
  # remote-state dependency is needed just to obtain the ARN.
  org_arn = "arn:aws:organizations::${data.terraform_remote_state.aws_organization.outputs.management_account_id}:organization/${data.terraform_remote_state.aws_organization.outputs.organization_id}"
}

module "aws_shared_services" {
  source = "../../modules/stages/aws-shared-services"

  org_id  = data.terraform_remote_state.aws_organization.outputs.organization_id
  org_arn = local.org_arn

  # ACM Private CA — org-shared internal certificate authority.
  enable_private_ca = var.enable_private_ca
  ca_common_name    = var.ca_common_name

  # Secrets Manager baseline — org-scoped secrets.
  enable_secrets_baseline = var.enable_secrets_baseline
  secrets                 = var.secrets
  secrets_kms_key_id      = var.secrets_kms_key_id
}
