# aws-backup stage (phase-2)
#
# Thin orchestration wrapper composing the organization backup baseline across
# two accounts:
#   - the DEFAULT provider authenticates into the MANAGEMENT account, which owns
#     the organization BACKUP_POLICY (an Organizations policy attached to the
#     Workloads OU).
#   - aws.backup targets the delegated BACKUP account, which owns the
#     KMS-encrypted, Compliance-mode Vault Lock (WORM) backup vault and the
#     restore testing plan.
#
# The vault is the WORM target for the org backup plan; the org policy points
# every account under the Workloads OU at the vault by name. The two children
# are joined by the vault name (backup_vault_name), which is the cross-account
# naming contract between the backup account's vault and the management
# account's policy.

# ---------------------------------------------------------------------------
# Backup vault + Vault Lock + restore testing (BACKUP account)
# ---------------------------------------------------------------------------

module "backup_vault" {
  source = "../../aws/backup-vault"
  providers = {
    aws = aws.backup
  }

  vault_name               = var.vault_name
  kms_key_arn              = var.kms_key_arn
  min_retention_days       = var.min_retention_days
  max_retention_days       = var.max_retention_days
  changeable_for_days      = var.changeable_for_days
  restore_testing_role_arn = var.restore_testing_role_arn
}

# ---------------------------------------------------------------------------
# Organization BACKUP_POLICY (MANAGEMENT account = default provider)
# ---------------------------------------------------------------------------

module "backup_org_policy" {
  source = "../../aws/backup-org-policy"

  backup_vault_name = var.vault_name
  backup_role_arn   = var.backup_role_arn
  target_ou_id      = var.workloads_ou_id
  default_region    = var.aws_region

  depends_on = [module.backup_vault]
}
