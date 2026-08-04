# Example: deploy an API Gateway backed by a Cloud Run service.
# The OpenAPI spec routes all traffic to the Cloud Run backend.

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
