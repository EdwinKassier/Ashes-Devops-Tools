# Phase-2 backup root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws-backup stage: a KMS-encrypted, Vault-Locked backup
# vault in the delegated backup account plus the organization BACKUP_POLICY
# attached to the Workloads OU. It is a CONSUMER of the cross-root contract
# (account_role_arns["backup"], ou_ids["Workloads"]).
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
    account_ids       = tomap(data.terraform_remote_state.aws_organization[0].outputs.account_ids)
    account_role_arns = tomap(data.terraform_remote_state.aws_organization[0].outputs.account_role_arns)
    ou_ids            = tomap(data.terraform_remote_state.aws_organization[0].outputs.ou_ids)
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

module "aws_backup" {
  source = "../../../modules/aws/stages/backup"

  # The default provider authenticates as / into the management account (which
  # owns the org BACKUP_POLICY), so it is mapped to the stage's default aws
  # provider. The backup account is an aliased provider assuming the cross-account
  # role from the organization remote state.
  providers = {
    aws        = aws
    aws.backup = aws.backup
  }

  # Cross-root contract: the org policy attaches to the Workloads OU published by
  # the aws-organization root.
  workloads_ou_id = local.org.ou_ids["Workloads"]

  aws_region = local.aws_region

  vault_name          = var.vault_name
  kms_key_arn         = var.kms_key_arn
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
  changeable_for_days = var.changeable_for_days

  backup_role_arn          = var.backup_role_arn
  backup_role_name         = var.backup_role_name
  restore_testing_role_arn = var.restore_testing_role_arn
}
