# Example: the application golden path for one service in a dev environment
# host project. It creates, for "orders-api":
#   - an Artifact Registry docker repo (immutable tags, CMEK, scan on push);
#   - a least-privilege runtime SA (orders-api-run) and a Cloud Run v2 service
#     with internal-only ingress, Direct VPC egress to private ranges, secrets
#     from Secret Manager and Binary Authorization enforced;
#   - a private-IP Cloud SQL Postgres (orders-api-db, CMEK, IAM auth) on the
#     Shared VPC's Private Service Access;
#   - a deploy SA (orders-api-deploy) impersonable only by GitHub Actions from
#     the repo's immutable numeric ID on refs/heads/main, via an app-only WIF pool;
#   - 5xx / p99 latency alerts and a 99.9% availability SLO with a burn-rate alert.
#
# In a real deployment gcp/stages/environment calls this stage with values from
# the gcp-projects and network remote state. The network, subnet, PSA range,
# KMS keys, secret and notification channel must already exist.
# Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

locals {
  host_project_id = "my-dev-host-project"
  region          = "europe-west2"
}

module "app_services" {
  source = "../../"

  project_id     = local.host_project_id
  project_number = "123456789012"
  region         = local.region
  environment    = "dev"

  network_id    = "projects/${local.host_project_id}/global/networks/dev-vpc"
  subnetwork_id = "projects/${local.host_project_id}/regions/${local.region}/subnetworks/dev-private"

  artifact_registry_kms_key_name = "projects/my-kms-project/locations/${local.region}/keyRings/dev-keyring/cryptoKeys/artifact-registry"

  # App-only Workload Identity pool (apps-dev), separate from the infra pool.
  enable_app_deploy_wif = true
  # Immutable numeric GitHub org ID: gh api orgs/<org> --jq .id
  github_repository_owner_id = "12345678"

  alert_notification_channel_ids = ["projects/${local.host_project_id}/notificationChannels/1234567890"]

  services = {
    orders-api = {
      # ingress defaults to INGRESS_TRAFFIC_INTERNAL_ONLY (no public URL).
      min_instances = 0
      max_instances = 5

      env_vars = {
        LOG_LEVEL = "info"
      }

      # The secret must already exist in the host project; the runtime SA gets
      # secretAccessor on exactly this secret.
      secrets = {
        STRIPE_API_KEY = { secret = "orders-api-stripe-key", version = "latest" }
      }

      enable_binary_authorization = true

      database = {
        databases           = ["orders"]
        encryption_key_name = "projects/my-kms-project/locations/${local.region}/keyRings/dev-keyring/cryptoKeys/cloudsql"
      }

      # Deploy identity bound to the repo's IMMUTABLE numeric ID
      # (gh api repos/<owner>/<repo> --jq .id).
      github = {
        repository_id = "987654321"
        repository    = "example-org/orders-api"
        ref           = "refs/heads/main"
      }

      slo = {
        sli_type               = "availability"
        goal                   = 0.999
        enable_burn_rate_alert = true
      }
    }
  }

  labels = {
    env = "dev"
  }
}
