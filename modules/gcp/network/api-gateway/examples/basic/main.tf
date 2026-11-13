# Example: deploy an API Gateway backed by a Cloud Run service.
# The OpenAPI spec routes all traffic to the Cloud Run backend.
#
# API Gateway calls the run.app URL from outside the VPC, so the backend needs
# ingress INGRESS_TRAFFIC_ALL (keep IAM auth on and grant the gateway service
# account roles/run.invoker). The landing zone's Cloud Run default (internal
# load-balancer ingress) and the run.allowedIngress org policy reject that;
# network/app-ingress (external HTTPS load balancer + Cloud Armor) is the
# golden path for public Cloud Run services.

locals {
  project_id = "my-workload-project"
  region     = "us-central1"
  # Service account that the gateway uses to invoke the Cloud Run backend.
  gateway_sa_email = "api-gateway@my-workload-project.iam.gserviceaccount.com"
}

module "api_gateway" {
  source = "../../"

  project_id            = local.project_id
  region                = local.region
  api_id                = "my-api"
  display_name          = "My API"
  gateway_id            = "my-api-gateway"
  service_account_email = local.gateway_sa_email

  openapi_spec = <<-YAML
    openapi: '3.0.0'
    info:
      title: My API
      version: '1.0.0'
    paths:
      /v1:
        get:
          summary: Proxy to Cloud Run
          operationId: proxyGet
          x-google-backend:
            address: https://api-xxxxxxxx-uc.a.run.app
          responses:
            '200':
              description: OK
  YAML
}
