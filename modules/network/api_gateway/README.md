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

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

API Gateway Module - Main Configuration

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	service_account_email = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | 6.50.0 |



## Resources

The following resources are created:


- resource.google-beta_google_api_gateway_api.api (modules/network/api_gateway/main.tf#L17)
- resource.google-beta_google_api_gateway_api_config.api_config (modules/network/api_gateway/main.tf#L26)
- resource.google-beta_google_api_gateway_gateway.gateway (modules/network/api_gateway/main.tf#L52)
- resource.google-beta_google_compute_region_network_endpoint_group.serverless_neg (modules/network/api_gateway/main.tf#L64)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the API Gateway will be created | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | The service account email to use for the API Gateway backend | `string` | n/a | yes |
| <a name="input_api_id"></a> [api\_id](#input\_api\_id) | Identifier to use for the API | `string` | `"ashes-api"` | no |
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Display name for the API | `string` | `"Ashes API Gateway"` | no |
| <a name="input_gateway_display_name"></a> [gateway\_display\_name](#input\_gateway\_display\_name) | Display name for the gateway instance | `string` | `"Ashes API Gateway Instance"` | no |
| <a name="input_gateway_id"></a> [gateway\_id](#input\_gateway\_id) | Identifier to use for this gateway instance | `string` | `"ashes-gateway"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the gateway | `map(string)` | <pre>{<br/>  "environment": "production",<br/>  "managed_by": "terraform"<br/>}</pre> | no |
| <a name="input_managed_service_ids"></a> [managed\_service\_ids](#input\_managed\_service\_ids) | A map of Service IDs to inject into the OpenAPI spec, replacing the need for external script discovery. | `map(string)` | `{}` | no |
| <a name="input_openapi_spec"></a> [openapi\_spec](#input\_openapi\_spec) | OpenAPI specification that will be used to configure the API | `string` | `"openapi: '3.0.0'\ninfo:\n  title: 'Ashes API Gateway'\n  version: '1.0.0'\npaths:\n  /health:\n    get:\n      summary: Health check endpoint\n      operationId: health\n      responses:\n        '200':\n          description: OK\n          content:\n            application/json:\n              schema:\n                type: object\n                properties:\n                  status:\n                    type: string\n"` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where the API Gateway will be deployed | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api"></a> [api](#output\_api) | The created API Gateway API resource |
| <a name="output_api_config"></a> [api\_config](#output\_api\_config) | The created API Gateway config resource |
| <a name="output_gateway"></a> [gateway](#output\_gateway) | The created API Gateway instance |
| <a name="output_gateway_default_hostname"></a> [gateway\_default\_hostname](#output\_gateway\_default\_hostname) | The default hostname of the API Gateway |
| <a name="output_id"></a> [id](#output\_id) | The ID of the API Gateway |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the API Gateway |
| <a name="output_serverless_neg_id"></a> [serverless\_neg\_id](#output\_serverless\_neg\_id) | The ID of the Serverless NEG for Load Balancer integration |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | The full service name used for the API Gateway |
<!-- END_TF_DOCS -->