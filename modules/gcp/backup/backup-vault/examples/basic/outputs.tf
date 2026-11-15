output "vault_id" {
  description = "Terraform ID of the backup vault."
  value       = module.backup_vault.vault_id
}

output "service_account" {
  description = "The vault's service agent."
  value       = module.backup_vault.service_account
}
