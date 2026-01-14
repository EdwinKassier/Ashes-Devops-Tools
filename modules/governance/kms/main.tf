/**
 * KMS Module - Customer-Managed Encryption Keys
 * Provides Keyrings and CryptoKeys for CMEK compliance
 */

# KMS Keyring
resource "google_kms_key_ring" "keyring" {
  name     = var.keyring_name
  location = var.location
  project  = var.project_id
}

# CryptoKeys with automatic rotation
resource "google_kms_crypto_key" "keys" {
  for_each = var.keys

  name            = each.key
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = each.value.rotation_period
  purpose         = try(each.value.purpose, "ENCRYPT_DECRYPT")

  version_template {
    algorithm        = try(each.value.algorithm, "GOOGLE_SYMMETRIC_ENCRYPTION")
    protection_level = try(each.value.protection_level, "SOFTWARE")
  }

  labels = merge(var.labels, try(each.value.labels, {}))

  lifecycle {
    prevent_destroy = true
  }
}

# IAM bindings for key access
resource "google_kms_crypto_key_iam_member" "key_iam" {
  for_each = {
    for binding in flatten([
      for key_name, key_config in var.keys : [
        for member in try(key_config.encrypter_decrypters, []) : {
          key           = "${key_name}-${member}"
          crypto_key_id = google_kms_crypto_key.keys[key_name].id
          role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
          member        = member
        }
      ]
    ]) : binding.key => binding
  }

  crypto_key_id = each.value.crypto_key_id
  role          = each.value.role
  member        = each.value.member
}
