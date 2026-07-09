output "vault_arn" {
  description = "ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account."
  value       = module.backup_vault.vault_arn
}

output "backup_policy_id" {
  description = "ID of the organization BACKUP_POLICY attached to the Workloads OU."
  value       = module.backup_org_policy.policy_id
}
