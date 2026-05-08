output "keyring_id" {
  description = "Fully-qualified keyring resource ID"
  value       = module.kms.keyring_id
}

output "key_ids" {
  description = "Map of key name → fully-qualified key ID"
  value       = module.kms.key_ids
}
