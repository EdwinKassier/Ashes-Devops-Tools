# Plan/apply assertions for the two app-ingress extensions: a CloudFront VPC
# origin (private ALB origin) and a REGIONAL Web ACL for an internet-facing ALB.

mock_provider "aws" {
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-2:111111111111:regional/webacl/test-regional/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/test-cf/00000000-0000-0000-0000-000000000000"
    }
  }
}

run "vpc_origin_fronts_private_alb" {
  command = apply

  variables {
    enable_edge              = true
    enable_vpc_origin        = true
    name_prefix              = "dev-apps"
    vpc_origin_arn           = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/dev-apps/0123456789abcdef"
    origin_domain_name       = "internal-dev-apps-123.eu-west-2.elb.amazonaws.com"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this) == 1 && aws_cloudfront_vpc_origin.this[0].vpc_origin_endpoint_config[0].arn == "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/dev-apps/0123456789abcdef"
    error_message = "enable_vpc_origin must create one VPC origin targeting the ALB"
  }

  assert {
    condition     = aws_cloudfront_vpc_origin.this[0].vpc_origin_endpoint_config[0].origin_protocol_policy == "http-only"
    error_message = "The VPC origin hop defaults to http-only (TLS terminates at CloudFront)"
  }

  assert {
    condition = (
      length(one(aws_cloudfront_distribution.this[0].origin).vpc_origin_config) == 1 &&
      length(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config) == 0
    )
    error_message = "The distribution origin must use vpc_origin_config, not a public custom origin"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this[0].default_cache_behavior[0].allowed_methods) == 7
    error_message = "allowed_methods must reach the default cache behavior"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.regional) == 0
    error_message = "No regional ACL unless enable_regional_waf"
  }
}

run "regional_waf_for_public_alb" {
  command = apply

  variables {
    enable_regional_waf       = true
    name_prefix               = "dev-apps"
    regional_waf_resource_arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/dev-apps/0123456789abcdef"
  }

  assert {
    condition     = aws_wafv2_web_acl.regional[0].scope == "REGIONAL" && length(aws_wafv2_web_acl.regional[0].rule) == 2
    error_message = "enable_regional_waf must create a REGIONAL ACL with the two managed rule groups"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.regional[0].resource_arn == "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/dev-apps/0123456789abcdef"
    error_message = "The regional ACL must be associated with regional_waf_resource_arn"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 0 && length(aws_cloudfront_vpc_origin.this) == 0
    error_message = "A regional WAF alone must not create CloudFront resources"
  }
}

run "default_has_no_vpc_origin_or_regional_acl" {
  command = apply

  variables {
    enable_edge = true
  }

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this) == 0 && length(aws_wafv2_web_acl.regional) == 0
    error_message = "Defaults must not create a VPC origin or a regional ACL"
  }

  assert {
    condition     = length(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config) == 1
    error_message = "Default origin stays a public HTTPS custom origin"
  }
}
