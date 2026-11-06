# Plan assertions for the kms module: verify keyring/key creation, for_each key
# sets, secure defaults (90-day rotation, symmetric ENCRYPT_DECRYPT, SOFTWARE
# protection), label merging, and the flattened encrypter/decrypter IAM fan-out.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {
  override_resource {
    target          = google_kms_key_ring.keyring
    override_during = plan
    values = {
      id = "projects/mock-project/locations/global/keyRings/test-keyring"
    }
  }
}

variables {
  project_id   = "mock-project"
  keyring_name = "test-keyring"
}

run "no_keys_by_default" {
  command = plan

  assert {
    condition     = google_kms_key_ring.keyring.location == "global"
    error_message = "Keyring location must default to global."
  }

  assert {
    condition     = length(google_kms_crypto_key.keys) == 0 && length(google_kms_crypto_key_iam_member.key_iam) == 0
    error_message = "With keys = {} no CryptoKeys or IAM members must be planned."
  }
}

run "keys_with_secure_defaults_and_iam" {
  command = plan

  variables {
    location = "europe-west1"
    labels   = { env = "prod", owner = "platform" }
    keys = {
      storage = {
        encrypter_decrypters = [
          "serviceAccount:gcs@mock-project.iam.gserviceaccount.com",
          "serviceAccount:app@mock-project.iam.gserviceaccount.com",
        ]
      }
      bigquery = {
        rotation_period  = "2592000s"
        protection_level = "HSM"
        labels           = { owner = "data", tier = "1" }
        encrypter_decrypters = [
          "serviceAccount:bq@mock-project.iam.gserviceaccount.com",
        ]
      }
    }
  }

  assert {
    condition     = google_kms_key_ring.keyring.location == "europe-west1"
    error_message = "Keyring location override must be honoured."
  }

  assert {
    condition     = toset(keys(google_kms_crypto_key.keys)) == toset(["storage", "bigquery"])
    error_message = "One CryptoKey must be planned per entry in var.keys, keyed by key name."
  }

  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.keys : v.name == k])
    error_message = "Each CryptoKey name must be its map key."
  }

  assert {
    condition     = alltrue([for v in google_kms_crypto_key.keys : v.key_ring == "projects/mock-project/locations/global/keyRings/test-keyring"])
    error_message = "Every CryptoKey must be created in the module's keyring."
  }

  assert {
    condition     = google_kms_crypto_key.keys["storage"].rotation_period == "7776000s"
    error_message = "rotation_period must default to 7776000s (90 days)."
  }

  assert {
    condition     = google_kms_crypto_key.keys["bigquery"].rotation_period == "2592000s"
    error_message = "Per-key rotation_period override must be honoured."
  }

  assert {
    condition     = google_kms_crypto_key.keys["storage"].purpose == "ENCRYPT_DECRYPT"
    error_message = "purpose must default to ENCRYPT_DECRYPT."
  }

  assert {
    condition     = google_kms_crypto_key.keys["storage"].version_template[0].algorithm == "GOOGLE_SYMMETRIC_ENCRYPTION" && google_kms_crypto_key.keys["storage"].version_template[0].protection_level == "SOFTWARE"
    error_message = "version_template must default to GOOGLE_SYMMETRIC_ENCRYPTION / SOFTWARE."
  }

  assert {
    condition     = google_kms_crypto_key.keys["bigquery"].version_template[0].protection_level == "HSM"
    error_message = "Per-key protection_level override (HSM) must be honoured."
  }

  assert {
    condition     = google_kms_crypto_key.keys["storage"].labels == tomap({ env = "prod", owner = "platform" })
    error_message = "Keys without their own labels must inherit the module-wide labels."
  }

  assert {
    condition     = google_kms_crypto_key.keys["bigquery"].labels == tomap({ env = "prod", owner = "data", tier = "1" })
    error_message = "Per-key labels must merge over (and override) the module-wide labels."
  }

  assert {
    condition = toset(keys(google_kms_crypto_key_iam_member.key_iam)) == toset([
      "storage-serviceAccount:gcs@mock-project.iam.gserviceaccount.com",
      "storage-serviceAccount:app@mock-project.iam.gserviceaccount.com",
      "bigquery-serviceAccount:bq@mock-project.iam.gserviceaccount.com",
    ])
    error_message = "IAM bindings must be flattened to one member per (key, encrypter_decrypter), keyed '<key>-<member>'."
  }

  assert {
    condition     = alltrue([for b in google_kms_crypto_key_iam_member.key_iam : b.role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"])
    error_message = "Every key IAM binding must grant only roles/cloudkms.cryptoKeyEncrypterDecrypter (least privilege)."
  }
}

run "asymmetric_signing_key_without_iam" {
  command = plan

  variables {
    keys = {
      signer = {
        purpose   = "ASYMMETRIC_SIGN"
        algorithm = "EC_SIGN_P256_SHA256"
      }
    }
  }

  assert {
    condition     = google_kms_crypto_key.keys["signer"].purpose == "ASYMMETRIC_SIGN" && google_kms_crypto_key.keys["signer"].version_template[0].algorithm == "EC_SIGN_P256_SHA256"
    error_message = "purpose/algorithm overrides must be honoured for asymmetric keys."
  }

  assert {
    condition     = google_kms_crypto_key.keys["signer"].rotation_period == null
    error_message = "asymmetric keys must not get a rotation_period (GCP only rotates symmetric ENCRYPT_DECRYPT keys)."
  }

  assert {
    condition     = length(google_kms_crypto_key_iam_member.key_iam) == 0
    error_message = "A key with no encrypter_decrypters must not create IAM bindings."
  }
}
