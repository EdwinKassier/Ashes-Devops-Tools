# Resource-assertion tests for the aws/edge-security module.
#
# The module declares a configuration_aliases [aws.us_east_1]; declaring a second
# mock_provider with that alias satisfies it automatically in `terraform test`.
# The distribution's web_acl_id references the Web ACL's computed ARN, so these
# runs use command = apply with mock_resource defaults rather than plan.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"
}

run "edge_enabled_provisions_cloudfront_waf" {
  command = apply

  variables {
    enable_edge = true
    name_prefix = "test"
  }

  assert {
    condition     = aws_wafv2_web_acl.cloudfront[0].scope == "CLOUDFRONT"
    error_message = "Web ACL must be CloudFront-scoped"
  }

  # Non-vacuous: prove at least one managed rule is attached to the Web ACL.
  assert {
    condition     = length(aws_wafv2_web_acl.cloudfront[0].rule) >= 1
    error_message = "Web ACL must carry at least one rule"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 1
    error_message = "A distribution must be created when edge is enabled"
  }
}

run "edge_disabled_provisions_nothing" {
  command = apply

  variables {
    enable_edge = false
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 0
    error_message = "No distribution must be created when edge is disabled"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.cloudfront) == 0
    error_message = "No Web ACL must be created when edge is disabled"
  }
}
