# Backup cross-root contract. These keys may be consumed by downstream aws roots
# via terraform_remote_state. Keep them stable across refactors.

output "vault_arn" {
  description = "ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account."
  value       = module.aws_backup.vault_arn
}

output "backup_policy_id" {
  description = "ID of the organization BACKUP_POLICY attached to the Workloads OU."
  value       = module.aws_backup.backup_policy_id
}
