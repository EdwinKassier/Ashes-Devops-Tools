# edge-security

Optional, workload-owned edge security stack for the SRA landing zone: a
CloudFront distribution fronted by a CloudFront-scoped WAFv2 Web ACL, an
optional ACM certificate for a custom domain, optional Shield Advanced
enrollment, and optional WAF logging.

CloudFront is a global service, so its WAF (`scope = "CLOUDFRONT"`) and ACM
certificate dependencies **must** live in `us-east-1`. The module therefore
declares a `us-east-1` aliased provider (`aws.us_east_1`) that the caller wires
up; all other behavior follows the workload's home Region.

This module is the per-workload complement to the org-wide guardrail. Firewall
Manager (module `aws/firewall-manager-org`, plan item C11) enforces a baseline
WAF policy across every account centrally; this module provisions the edge a
single workload chooses to stand up in front of its own application. Everything
is count-gated on `enable_edge` (default `false`), so the module is inert until
a workload opts in. Shield Advanced is additionally gated behind `enable_shield`
because it carries a substantial monthly subscription cost.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_acm_certificate.this (modules/aws/security/edge-security/main.tf#L91)
- resource.aws_cloudfront_distribution.this (modules/aws/security/edge-security/main.tf#L104)
- resource.aws_cloudfront_vpc_origin.this (modules/aws/security/edge-security/main.tf#L214)
- resource.aws_shield_protection.this (modules/aws/security/edge-security/main.tf#L189)
- resource.aws_wafv2_web_acl.cloudfront (modules/aws/security/edge-security/main.tf#L19)
- resource.aws_wafv2_web_acl.regional (modules/aws/security/edge-security/main.tf#L243)
- resource.aws_wafv2_web_acl_association.regional (modules/aws/security/edge-security/main.tf#L309)
- resource.aws_wafv2_web_acl_logging_configuration.regional (modules/aws/security/edge-security/main.tf#L315)
- resource.aws_wafv2_web_acl_logging_configuration.this (modules/aws/security/edge-security/main.tf#L198)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_methods"></a> [allowed\_methods](#input\_allowed\_methods) | HTTP methods the default cache behavior forwards. Default GET/HEAD (static content); an application origin needs ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]. | `list(string)` | <pre>[<br/>  "GET",<br/>  "HEAD"<br/>]</pre> | no |
| <a name="input_cache_policy_id"></a> [cache\_policy\_id](#input\_cache\_policy\_id) | ID of the CloudFront cache policy for the default behavior. Defaults to the AWS managed "CachingOptimized" policy. | `string` | `"658327ea-f89d-4fab-a63d-7e88639e58f6"` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain for the distribution. When set, an ACM certificate (DNS validation, us-east-1) is created and attached; when empty, the default CloudFront certificate is used. | `string` | `""` | no |
| <a name="input_enable_edge"></a> [enable\_edge](#input\_enable\_edge) | Master switch. When false, the module provisions nothing (all resources are count-gated on this). | `bool` | `false` | no |
| <a name="input_enable_regional_waf"></a> [enable\_regional\_waf](#input\_enable\_regional\_waf) | Create a REGIONAL WAFv2 Web ACL (AWS Common + KnownBadInputs managed rule groups) in the default provider's region and associate it with regional\_waf\_resource\_arn. Independent of enable\_edge. | `bool` | `false` | no |
| <a name="input_enable_shield"></a> [enable\_shield](#input\_enable\_shield) | Enroll the distribution in AWS Shield Advanced. Off by default because Shield Advanced carries a substantial monthly subscription cost. | `bool` | `false` | no |
| <a name="input_enable_vpc_origin"></a> [enable\_vpc\_origin](#input\_enable\_vpc\_origin) | Front a PRIVATE load balancer through a CloudFront VPC origin (aws\_cloudfront\_vpc\_origin) instead of a public custom origin. Requires vpc\_origin\_arn; origin\_domain\_name should be the load balancer's DNS name. The origin VPC must have an internet gateway attached. | `bool` | `false` | no |
| <a name="input_log_destination_arn"></a> [log\_destination\_arn](#input\_log\_destination\_arn) | ARN of the log destination (Kinesis Data Firehose, CloudWatch log group, or S3 bucket) for WAF Web ACL logs. When empty, WAF logging is not configured. | `string` | `""` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the WAF Web ACL, CloudFront Shield protection, and metric names. | `string` | `"edge"` | no |
| <a name="input_origin_domain_name"></a> [origin\_domain\_name](#input\_origin\_domain\_name) | DNS name of the origin CloudFront fetches from (an ALB, S3 website endpoint, or arbitrary host). | `string` | `"origin.example.com"` | no |
| <a name="input_origin_request_policy_id"></a> [origin\_request\_policy\_id](#input\_origin\_request\_policy\_id) | ID of the CloudFront origin request policy for the default behavior (which viewer headers, cookies and query strings reach the origin). Null forwards none beyond the cache key. For an application origin use the managed "AllViewerExceptHostHeader" policy (b689b0a8-53d0-40ab-baf2-68738e2966ac). | `string` | `null` | no |
| <a name="input_regional_waf_resource_arn"></a> [regional\_waf\_resource\_arn](#input\_regional\_waf\_resource\_arn) | ARN of the regional resource (ALB, API Gateway stage, AppSync API, Cognito user pool) the regional Web ACL is associated with. Required when enable\_regional\_waf is true. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |
| <a name="input_vpc_origin_arn"></a> [vpc\_origin\_arn](#input\_vpc\_origin\_arn) | ARN of the internal ALB / NLB (or EC2 instance) the VPC origin targets. Required when enable\_vpc\_origin is true. | `string` | `""` | no |
| <a name="input_vpc_origin_http_port"></a> [vpc\_origin\_http\_port](#input\_vpc\_origin\_http\_port) | Port CloudFront uses for HTTP to the VPC origin. | `number` | `80` | no |
| <a name="input_vpc_origin_https_port"></a> [vpc\_origin\_https\_port](#input\_vpc\_origin\_https\_port) | Port CloudFront uses for HTTPS to the VPC origin. | `number` | `443` | no |
| <a name="input_vpc_origin_protocol_policy"></a> [vpc\_origin\_protocol\_policy](#input\_vpc\_origin\_protocol\_policy) | Protocol CloudFront uses to the VPC origin: http-only (default; the hop stays inside the VPC on CloudFront-managed ENIs and TLS terminates at CloudFront), https-only, or match-viewer. https-only requires the origin certificate to match origin\_domain\_name. | `string` | `"http-only"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Domain name of the CloudFront distribution, or null when edge is disabled. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution, or null when edge is disabled. |
| <a name="output_regional_web_acl_arn"></a> [regional\_web\_acl\_arn](#output\_regional\_web\_acl\_arn) | ARN of the REGIONAL WAFv2 Web ACL, or null when enable\_regional\_waf is false. |
| <a name="output_vpc_origin_id"></a> [vpc\_origin\_id](#output\_vpc\_origin\_id) | ID of the CloudFront VPC origin, or null when enable\_vpc\_origin is false. |
| <a name="output_web_acl_arn"></a> [web\_acl\_arn](#output\_web\_acl\_arn) | ARN of the CloudFront-scoped WAFv2 Web ACL, or null when edge is disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
# CloudFront's WAF + ACM dependencies are global and must live in us-east-1.
provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "edge_security" {
  source = "../../modules/aws/edge-security"

  enable_edge        = true
  name_prefix        = "shop"
  origin_domain_name = "alb.internal.example.com"
  domain_name        = "shop.example.com" # triggers an ACM cert in us-east-1

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
