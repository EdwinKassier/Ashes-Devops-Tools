# Example: an HTTPS front door for an existing Cloud Run service. A global
# external load balancer with a reserved anycast IP, a Google-managed
# certificate, HTTP-to-HTTPS redirect, a Cloud Armor policy at the edge, a
# MODERN/RESTRICTED SSL policy as the TLS floor, and a Cloud DNS A record.
#
# Pair it with a Cloud Run service on INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER
# (the gcp/compute/cloud-run default) so the run.app URL is not reachable
# directly. The Cloud Armor policy, SSL policy and DNS zone must already exist
# (e.g. from gcp/network/cloud-armor and gcp/network/dns). The certificate
# provisions once the domain resolves to the load balancer IP.
# Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "ingress" {
  source = "../../"

  project_id = "my-project-id"
  region     = "europe-west2"
  name       = "orders-api"

  domains                = ["api.example.com"]
  cloud_run_service_name = "orders-api"

  security_policy_id = "projects/my-project-id/global/securityPolicies/edge-waf"
  ssl_policy_id      = "projects/my-project-id/global/sslPolicies/tls12-modern"

  dns_managed_zone = "example-com"
  dns_ttl          = 300

  labels = {
    app = "orders-api"
  }
}
