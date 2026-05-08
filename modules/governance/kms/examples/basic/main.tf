# Example: create a KMS keyring with two keys — one for CMEK encryption and
# one for signing — with 30-day rotation and IAM access granted to a service account.
# In a real deployment replace the locals below with data sources or remote state.

locals {
  project_id = "my-project-id"
  location   = "europe-west1"

  # Service account that will encrypt/decrypt with the data key
  app_sa = "serviceAccount:app@my-project-id.iam.gserviceaccount.com"
}

module "kms" {
  source = "../../"

  project_id   = local.project_id
  keyring_name = "app-keyring"
  location     = local.location

  keys = {
    data-encryption-key = {
      rotation_period      = "2592000s" # 30 days
      purpose              = "ENCRYPT_DECRYPT"
      algorithm            = "GOOGLE_SYMMETRIC_ENCRYPTION"
      protection_level     = "SOFTWARE"
      encrypter_decrypters = [local.app_sa]
      labels               = { use = "cmek" }
    }

    signing-key = {
      rotation_period  = "7776000s" # 90 days (max)
      purpose          = "ASYMMETRIC_SIGN"
      algorithm        = "RSA_SIGN_PKCS1_4096_SHA512"
      protection_level = "SOFTWARE"
      labels           = { use = "signing" }
    }
  }

  labels = {
    environment = "dev"
    managed-by  = "terraform"
  }
}
