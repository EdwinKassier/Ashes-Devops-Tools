output "managed_secrets" {
  description = "List of secret names that are managed in this Supabase Vault."
  value       = module.vault_secrets.managed_secret_names
}
