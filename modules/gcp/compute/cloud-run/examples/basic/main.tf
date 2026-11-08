# Example: a private Cloud Run (v2) service that runs as a dedicated service
# account, is reachable only through an internal load balancer, reads its
# database password from Secret Manager, egresses to the VPC over Direct VPC
# egress (private ranges only) and enforces the project's Binary Authorization
# policy. No unauthenticated access.
#
# The service account, secret, subnet and image must already exist (e.g. from
# gcp/iam/service-account, gcp/data/secret-manager, gcp/network/tiered-vpc and
# gcp/artifact-registry). Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "cloud_run" {
  source = "../../"

  project_id            = "my-project-id"
  location              = "europe-west2"
  name                  = "orders-api"
  image                 = "europe-west2-docker.pkg.dev/my-project-id/apps/orders-api:1.0.0"
  service_account_email = "orders-api-run@my-project-id.iam.gserviceaccount.com"

  env_vars = {
    LOG_LEVEL = "info"
  }

  # Secret material is wired by reference, never passed as plaintext.
  secret_env_vars = [
    { name = "DB_PASSWORD", secret = "orders-db-password", version = "latest" },
  ]

  cpu                = "1"
  memory             = "512Mi"
  min_instance_count = 0
  max_instance_count = 10

  # Default, shown for clarity: no public run.app traffic.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  vpc_access = {
    egress = "PRIVATE_RANGES_ONLY"
    network_interfaces = {
      network    = "projects/my-host-project/global/networks/shared-vpc"
      subnetwork = "projects/my-host-project/regions/europe-west2/subnetworks/app-subnet"
    }
  }

  # Enforce the project's default Binary Authorization policy.
  binary_authorization = {}

  labels = {
    app = "orders-api"
  }
}
