output "vault_arn" {
  description = "ARN of the Vault-Locked backup vault in the backup account."
  value       = module.aws_backup.vault_arn
}

output "backup_policy_id" {
  description = "ID of the organization BACKUP_POLICY attached to the Workloads OU."
  value       = module.aws_backup.backup_policy_id
}
