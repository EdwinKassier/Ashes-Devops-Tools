# Example: KMS keyring with two keys — one for application data encryption,
# one for log encryption. Both rotate every 90 days (the default).
# Replace the project_id with your real project.

module "kms" {
  source = "../../modules/governance/kms"

  project_id   = "my-project-id"
  keyring_name = "app-keyring"
  location     = "europe-west1"

  keys = {
    "app-data-key" = {
      rotation_period = "7776000s" # 90 days
      iam_bindings = {
        "roles/cloudkms.cryptoKeyEncrypterDecrypter" = [
          "serviceAccount:my-app@my-project-id.iam.gserviceaccount.com"
        ]
      }
    }
    "log-encryption-key" = {
      rotation_period = "7776000s"
      iam_bindings    = {}
    }
  }

  labels = {
    environment = "production"
    managed-by  = "terraform"
  }
}

output "app_key_id" {
  description = "KMS key ID for application data encryption"
  value       = module.kms.key_ids["app-data-key"]
}
