# API Gateway Module

This module provisions a Google Cloud API Gateway, including the API Config and Gateway capability. It handles the deployment of OpenAPI specs.

## Features

- **OpenAPI Management**: Deploys API definitions from an OpenAPI spec file.
- **Service Injection**: Dynamically injects backend service URLs into the OpenAPI spec template.
- **Serverless NEG**: Automatically creates a Serverless Network Endpoint Group (NEG) for integration with Global Load Balancers.

## Usage

```hcl
module "api_gateway" {
  source = "./modules/network/api_gateway"

  project_id = "my-project-id"
  api_id     = "my-api"
  region     = "us-central1"

  openapi_spec_path = "api-spec.yaml.tftpl"
  
  managed_service_ids = {
    "users-service" = "https://users-run-service-url..."
    "auth-service"  = "https://auth-run-service-url..."
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `api_id` | Identifier for the API | `string` | n/a | yes |
| `region` | GCP Region | `string` | n/a | yes |
| `openapi_spec_path` | Path to OpenAPI template file | `string` | n/a | yes |
| `managed_service_ids` | Map of service names to URLs | `map(string)` | `{}` | no |
| `display_name` | Display name for the API | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| `gateway` | The Gateway resource |
| `id` | The Gateway ID |
| `self_link` | The Gateway URI |
| `gateway_url` | The public URL of the gateway |
| `serverless_neg_id` | ID of the Serverless NEG |
