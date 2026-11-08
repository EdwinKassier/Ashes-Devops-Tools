# Example: two Secret Manager secrets for an application, replicated only to
# europe-west2 and encrypted with a regional CMEK key. The database password
# gets an initial version from an ephemeral, sensitive root variable, written
# with the write-only secret_data_wo argument, so the plaintext never lands in
# plan or state. The API key secret is a container only; its value is added
# out of band. The runtime service account gets secretAccessor on each one.
#
# Supply the password with TF_VAR_orders_db_password (or a TFC sensitive
# variable); never commit it. The Secret Manager service agent needs
# roles/cloudkms.cryptoKeyEncrypterDecrypter on the key.
# Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

locals {
  kms_key     = "projects/my-kms-project/locations/europe-west2/keyRings/app-keyring/cryptoKeys/secrets-key"
  runtime_sa  = "serviceAccount:orders-api-run@my-project-id.iam.gserviceaccount.com"
  replication = { automatic = false, user_managed_regions = ["europe-west2"] }
}

module "secrets" {
  source = "../../"

  project_id = "my-project-id"

  secrets = {
    orders-db-password = {
      replication     = local.replication
      kms_key_name    = local.kms_key
      ephemeral_value = true
    }
    orders-payments-api-key = {
      replication  = local.replication
      kms_key_name = local.kms_key
    }
  }

  ephemeral_secret_values = {
    orders-db-password = var.orders_db_password
  }

  secret_accessors = {
    orders-db-password      = [local.runtime_sa]
    orders-payments-api-key = [local.runtime_sa]
  }

  labels = {
    app = "orders"
  }
}
