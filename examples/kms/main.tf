# Example: KMS keyring with two keys — one for application data encryption,
# one for log encryption. Both rotate every 90 days (the default).
# Replace the project_id with your real project.

module "kms" {
  source = "../../modules/gcp/governance/kms"

  project_id   = "my-project-id"
  keyring_name = "app-keyring"
  location     = "europe-west1"

  keys = {
    "app-data-key" = {
      rotation_period = "7776000s" # 90 days
      # Granted roles/cloudkms.cryptoKeyEncrypterDecrypter on this key (the
      # only role the module grants; it is additive, not authoritative).
      encrypter_decrypters = [
        "serviceAccount:my-app@my-project-id.iam.gserviceaccount.com"
      ]
    }
    "log-encryption-key" = {
      rotation_period = "7776000s"
      # No grant here: add the log sink's or service agent's identity per use case.
    }
  }

  labels = {
    environment = "production"
    managed-by  = "terraform"
  }
}
