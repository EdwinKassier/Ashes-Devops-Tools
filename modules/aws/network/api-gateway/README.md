# api-gateway (AWS)

API Gateway v2 (HTTP API) primitive for the SRA landing zone — the AWS parity
counterpart to `modules/gcp/network/api-gateway`. Creates an HTTP API with an
auto-deployed stage, structured JSON access logging to CloudWatch (retention +
optional KMS), optional routes/integrations, and an optional custom domain.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_apigatewayv2_api.this (modules/aws/network/api-gateway/main.tf#L48)
- resource.aws_apigatewayv2_api_mapping.this (modules/aws/network/api-gateway/main.tf#L121)
- resource.aws_apigatewayv2_domain_name.this (modules/aws/network/api-gateway/main.tf#L107)
- resource.aws_apigatewayv2_integration.this (modules/aws/network/api-gateway/main.tf#L70)
- resource.aws_apigatewayv2_route.this (modules/aws/network/api-gateway/main.tf#L79)
- resource.aws_apigatewayv2_stage.this (modules/aws/network/api-gateway/main.tf#L92)
- resource.aws_cloudwatch_log_group.access (modules/aws/network/api-gateway/main.tf#L38)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name of the API. Used for the aws\_apigatewayv2\_api name and as the prefix for the access-log group. | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN for the custom domain. Required when enable\_custom\_domain = true; must be in the API's region for regional HTTP APIs. | `string` | `""` | no |
| <a name="input_cors_configuration"></a> [cors\_configuration](#input\_cors\_configuration) | Optional CORS configuration for the HTTP API. Set to null to disable CORS<br/>(the default). When set, all fields are optional and map directly onto the<br/>aws\_apigatewayv2\_api cors\_configuration block. | <pre>object({<br/>    allow_credentials = optional(bool)<br/>    allow_headers     = optional(list(string))<br/>    allow_methods     = optional(list(string))<br/>    allow_origins     = optional(list(string))<br/>    expose_headers    = optional(list(string))<br/>    max_age           = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description of the API. | `string` | `"Managed by Terraform."` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain name to attach (e.g. api.example.com). Only used when enable\_custom\_domain = true. | `string` | `""` | no |
| <a name="input_enable_custom_domain"></a> [enable\_custom\_domain](#input\_enable\_custom\_domain) | Create a custom domain name and map it to the stage. Requires domain\_name and certificate\_arn. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Optional KMS key ARN for encrypting the access-log group. Empty string uses the default CloudWatch Logs encryption. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention, in days, for the access-log CloudWatch log group. | `number` | `365` | no |
| <a name="input_protocol_type"></a> [protocol\_type](#input\_protocol\_type) | Protocol for the API. HTTP (HTTP API, the modern default) or WEBSOCKET. | `string` | `"HTTP"` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Routes to create on the API. Each entry produces one aws\_apigatewayv2\_route<br/>plus its backing aws\_apigatewayv2\_integration. Default empty = no routes<br/>(the API is created bare, for callers that manage routes elsewhere).<br/>  - route\_key:          e.g. "GET /items" or "$default"<br/>  - integration\_uri:    backend URI (Lambda ARN, HTTP URL, ...)<br/>  - integration\_type:   AWS\_PROXY \| HTTP\_PROXY \| HTTP \| MOCK<br/>  - authorization\_type: NONE \| AWS\_IAM \| JWT \| CUSTOM (default AWS\_IAM — secure by default)<br/>  - authorizer\_id:      required when authorization\_type is JWT or CUSTOM | <pre>list(object({<br/>    route_key          = string<br/>    integration_uri    = string<br/>    integration_type   = optional(string, "AWS_PROXY")<br/>    authorization_type = optional(string, "AWS_IAM")<br/>    authorizer_id      = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_stage_name"></a> [stage\_name](#input\_stage\_name) | Name of the (auto-deployed) stage. Use "$default" for the default stage. | `string` | `"$default"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all taggable resources this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_arn"></a> [api\_arn](#output\_api\_arn) | The ARN of the API. |
| <a name="output_api_endpoint"></a> [api\_endpoint](#output\_api\_endpoint) | The default endpoint (URI) of the API. |
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | The identifier of the HTTP API. |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | The ARN of the access-log CloudWatch log group. |
| <a name="output_stage_arn"></a> [stage\_arn](#output\_stage\_arn) | The ARN of the stage. |
| <a name="output_stage_invoke_url"></a> [stage\_invoke\_url](#output\_stage\_invoke\_url) | The invoke URL of the stage. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "api" {
  source = "../../modules/aws/network/api-gateway"

  name          = "orders-api"
  protocol_type = "HTTP"

  cors_configuration = {
    allow_origins = ["https://app.example.com"]
    allow_methods = ["GET", "POST"]
  }

  routes = [
    {
      route_key       = "GET /items"
      integration_uri = "arn:aws:lambda:eu-west-1:123456789012:function:list-items"
    },
  ]

  log_retention_days = 365

  tags = {
    "managed-by" = "terraform"
  }
}
```
