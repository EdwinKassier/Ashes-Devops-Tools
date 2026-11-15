# Example: create a global HTTPS load balancer with Cloud CDN in front of a
# Cloud Run NEG backend.

locals {
  project_id = "my-workload-project"
  # Serverless NEG self-link for the Cloud Run service.
  cloud_run_neg = "projects/my-workload-project/regions/us-central1/networkEndpointGroups/api-neg"
  # Cloud Armor policy for the public edge (network/cloud-armor output).
  cloud_armor_policy = "projects/my-workload-project/global/securityPolicies/api-edge-policy"
}

module "api_cdn" {
  source = "../../"

  project_id = local.project_id
  lb_name    = "api-global-lb"
  domains    = ["api.example.com"]

  backend_groups = [
    { group = local.cloud_run_neg }
  ]

  # Every internet-facing backend gets a Cloud Armor policy.
  security_policy = local.cloud_armor_policy

  enable_cdn           = true
  enable_http_redirect = true
}
