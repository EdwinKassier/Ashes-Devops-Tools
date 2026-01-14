output "keyring_id" {
  description = "ID of the KMS Keyring"
  value       = google_kms_key_ring.keyring.id
}

output "keyring_name" {
  description = "Name of the KMS Keyring"
  value       = google_kms_key_ring.keyring.name
}

output "key_ids" {
  description = "Map of CryptoKey IDs"
  value       = { for k, v in google_kms_crypto_key.keys : k => v.id }
}

output "key_names" {
  description = "Map of CryptoKey names (for use in resource configs)"
  value       = { for k, v in google_kms_crypto_key.keys : k => v.name }
}
