# Example: a private-IP-only Cloud SQL for PostgreSQL 16 instance, peered
# into a Shared VPC over Private Service Access, encrypted with a CMEK key,
# with regional HA, point-in-time recovery and IAM database authentication.
# The application connects as an IAM service-account user, so no database
# password exists anywhere in this configuration.
#
# Private Service Access must already be set up on the network, and the
# Cloud SQL service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on
# the key. If you need a built-in password user, see the module's `users` and
# ephemeral `user_passwords` inputs (write-only, never in state).
# Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "cloud_sql" {
  source = "../../"

  project_id = "my-project-id"
  region     = "europe-west2"
  name       = "orders-db"

  database_version = "POSTGRES_16"
  tier             = "db-custom-2-7680"

  private_network = "projects/my-host-project/global/networks/shared-vpc"

  encryption_key_name = "projects/my-kms-project/locations/europe-west2/keyRings/data-keyring/cryptoKeys/cloudsql-key"

  enable_high_availability       = true
  enable_point_in_time_recovery  = true
  transaction_log_retention_days = 7
  enable_iam_authentication      = true

  databases = ["orders"]

  users = [
    # Postgres IAM SA users drop the ".gserviceaccount.com" suffix.
    { name = "orders-api-run@my-project-id.iam", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
  ]

  labels = {
    app = "orders"
  }
}
