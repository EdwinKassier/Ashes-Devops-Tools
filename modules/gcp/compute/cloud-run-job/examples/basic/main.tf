# Example: a nightly-style batch Cloud Run job that runs five tasks (two at a
# time) as a dedicated service account, reads its database password from
# Secret Manager, egresses to the VPC over Direct VPC egress (private ranges
# only) and enforces the project's Binary Authorization policy.
#
# Trigger it with Cloud Scheduler or the delivery pipeline. The service
# account, secret, subnet and image must already exist. Replace the
# placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "cloud_run_job" {
  source = "../../"

  project_id            = "my-project-id"
  location              = "europe-west2"
  name                  = "orders-reconcile"
  image                 = "europe-west2-docker.pkg.dev/my-project-id/apps/orders-reconcile:1.0.0"
  service_account_email = "orders-reconcile-job@my-project-id.iam.gserviceaccount.com"

  task_count  = 5
  parallelism = 2
  max_retries = 3
  timeout     = "900s"

  env_vars = {
    LOG_LEVEL = "info"
  }

  # Secret material is wired by reference, never passed as plaintext.
  secret_env_vars = [
    { name = "DB_PASSWORD", secret = "orders-db-password", version = "latest" },
  ]

  vpc_access = {
    egress = "PRIVATE_RANGES_ONLY"
    network_interfaces = {
      network    = "projects/my-host-project/global/networks/shared-vpc"
      subnetwork = "projects/my-host-project/regions/europe-west2/subnetworks/app-subnet"
    }
  }

  binary_authorization = {}

  labels = {
    app = "orders-reconcile"
  }
}
