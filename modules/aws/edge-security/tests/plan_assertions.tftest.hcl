# Resource-assertion tests for the aws/edge-security module.
#
# The module declares a configuration_aliases [aws.us_east_1]; declaring a second
# mock_provider with that alias satisfies it automatically in `terraform test`.
# The distribution's web_acl_id references the Web ACL's computed ARN, so these
# runs use command = apply with mock_resource defaults rather than plan.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"

  # The WAF logging configuration's resource_arn references the Web ACL's
  # computed arn, and the provider validates it as a real ARN. Pin a valid
  # default arn for the Web ACL so the logging-config run does not trip
  # provider-side ARN validation on a random mock string.
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/test-cf/00000000-0000-0000-0000-000000000000"
    }
  }
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

run "edge_with_log_destination_provisions_logging_config" {
  command = apply

  variables {
    enable_edge         = true
    name_prefix         = "test"
    log_destination_arn = "arn:aws:kinesisfirehose:eu-west-2:111111111111:deliverystream/aws-waf-logs-x"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 1
    error_message = "A WAF logging configuration must be created when a log destination is supplied"
  }

  assert {
    # Non-vacuous: the logging config must actually target the supplied destination.
    condition     = contains(aws_wafv2_web_acl_logging_configuration.this[0].log_destination_configs, "arn:aws:kinesisfirehose:eu-west-2:111111111111:deliverystream/aws-waf-logs-x")
    error_message = "The logging configuration must ship to the supplied log destination arn"
  }
}

run "edge_without_log_destination_creates_no_logging_config" {
  command = apply

  variables {
    enable_edge         = true
    name_prefix         = "test"
    log_destination_arn = ""
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 0
    error_message = "No WAF logging configuration must be created when no log destination is supplied"
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
