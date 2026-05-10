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

output "keyring_location" {
  description = "The GCP location (region or 'global') where the KMS keyring was created."
  value       = google_kms_key_ring.keyring.location
}

output "keyring_self_link" {
  description = "The full resource name of the KMS keyring: projects/<project>/locations/<location>/keyRings/<name>."
  value       = google_kms_key_ring.keyring.id
}

output "key_self_links" {
  description = "Map of key name to full resource name (projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>)."
  value       = { for k, v in google_kms_crypto_key.keys : k => v.id }
}

output "key_rotation_periods" {
  description = "Map of key name to rotation period string (e.g. '7776000s'). Null for keys without rotation configured."
  value       = { for k, v in google_kms_crypto_key.keys : k => v.rotation_period }
}
