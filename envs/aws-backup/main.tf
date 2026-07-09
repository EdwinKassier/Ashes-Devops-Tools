# Phase-2 backup root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws-backup stage: a KMS-encrypted, Vault-Locked backup
# vault in the delegated backup account plus the organization BACKUP_POLICY
# attached to the Workloads OU. It is a CONSUMER of the cross-root contract
# (account_role_arns["backup"], ou_ids["Workloads"]).
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

module "aws_backup" {
  source = "../../modules/stages/aws-backup"

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
  workloads_ou_id = data.terraform_remote_state.aws_organization.outputs.ou_ids["Workloads"]

  aws_region = var.aws_region

  vault_name          = var.vault_name
  kms_key_arn         = var.kms_key_arn
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
  changeable_for_days = var.changeable_for_days

  backup_role_arn          = var.backup_role_arn
  restore_testing_role_arn = var.restore_testing_role_arn
}
