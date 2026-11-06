output "vault_arn" {
  description = "ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account."
  value       = module.backup_vault.vault_arn
}

output "backup_policy_id" {
  description = "ID of the organization BACKUP_POLICY attached to the Workloads OU."
  value       = module.backup_org_policy.policy_id
}

output "backup_role_arn" {
  description = "Member-account backup role ARN rendered into the org BACKUP_POLICY ($account-templated when the stage's StackSet deploys the role)."
  value       = local.backup_role_arn
}

output "restore_testing_role_arn" {
  description = "ARN of the restore-testing role in the backup account (created by the stage unless restore_testing_role_arn was set)."
  value       = module.backup_vault.restore_testing_role_arn
}
