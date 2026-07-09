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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_acm_certificate.this (modules/aws/edge-security/main.tf#L81)
- resource.aws_cloudfront_distribution.this (modules/aws/edge-security/main.tf#L92)
- resource.aws_shield_protection.this (modules/aws/edge-security/main.tf#L148)
- resource.aws_wafv2_web_acl.cloudfront (modules/aws/edge-security/main.tf#L16)
- resource.aws_wafv2_web_acl_logging_configuration.this (modules/aws/edge-security/main.tf#L156)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cache_policy_id"></a> [cache\_policy\_id](#input\_cache\_policy\_id) | ID of the CloudFront cache policy for the default behavior. Defaults to the AWS managed "CachingOptimized" policy. | `string` | `"658327ea-f89d-4fab-a63d-7e88639e58f6"` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain for the distribution. When set, an ACM certificate (DNS validation, us-east-1) is created and attached; when empty, the default CloudFront certificate is used. | `string` | `""` | no |
| <a name="input_enable_edge"></a> [enable\_edge](#input\_enable\_edge) | Master switch. When false, the module provisions nothing (all resources are count-gated on this). | `bool` | `false` | no |
| <a name="input_enable_shield"></a> [enable\_shield](#input\_enable\_shield) | Enroll the distribution in AWS Shield Advanced. Off by default because Shield Advanced carries a substantial monthly subscription cost. | `bool` | `false` | no |
| <a name="input_log_destination_arn"></a> [log\_destination\_arn](#input\_log\_destination\_arn) | ARN of the log destination (Kinesis Data Firehose, CloudWatch log group, or S3 bucket) for WAF Web ACL logs. When empty, WAF logging is not configured. | `string` | `""` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to the WAF Web ACL, CloudFront Shield protection, and metric names. | `string` | `"edge"` | no |
| <a name="input_origin_domain_name"></a> [origin\_domain\_name](#input\_origin\_domain\_name) | DNS name of the origin CloudFront fetches from (an ALB, S3 website endpoint, or arbitrary host). | `string` | `"origin.example.com"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Domain name of the CloudFront distribution, or null when edge is disabled. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution, or null when edge is disabled. |
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
