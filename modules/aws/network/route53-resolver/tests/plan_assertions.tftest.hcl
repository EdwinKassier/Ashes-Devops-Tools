# Resource-assertion tests for the aws/route53-resolver module.
#
# Asserts on configured attributes and on count-gated resource counts that are
# known at plan time under mock_provider. Provider-computed attributes (ids,
# arns) are not asserted on.

mock_provider "aws" {}

run "resolver_and_firewall_configured" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = aws_route53_resolver_endpoint.inbound.direction == "INBOUND"
    error_message = "Inbound resolver endpoint must have direction INBOUND."
  }

  assert {
    condition     = aws_route53_resolver_endpoint.outbound.direction == "OUTBOUND"
    error_message = "Outbound resolver endpoint must have direction OUTBOUND."
  }

  # DNS firewall is on by default: exactly one rule group must exist.
  assert {
    condition     = length(aws_route53_resolver_firewall_rule_group.this) == 1
    error_message = "DNS Firewall rule group must be created when enable_dns_firewall is true (default)."
  }

  assert {
    condition     = aws_route53_resolver_firewall_rule.block[0].action == "BLOCK"
    error_message = "DNS Firewall rule must use action BLOCK."
  }

  assert {
    condition     = aws_route53_resolver_firewall_config.this[0].firewall_fail_open == "DISABLED"
    error_message = "DNS Firewall must fail closed (firewall_fail_open = DISABLED)."
  }

  # Query logging is on by default: exactly one config + association.
  assert {
    condition     = length(aws_route53_resolver_query_log_config.this) == 1
    error_message = "Query log config must be created when enable_query_logging is true (default)."
  }

  # DNSSEC is off by default.
  assert {
    condition     = length(aws_route53_resolver_dnssec_config.this) == 0
    error_message = "DNSSEC config must not be created when enable_dnssec is false (default)."
  }
}

run "forward_rules_created" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    forward_rules = {
      corp = {
        domain_name = "corp.example.com"
        target_ips  = ["10.0.0.2", "10.0.1.2"]
      }
    }
  }

  assert {
    condition     = aws_route53_resolver_rule.fwd["corp"].rule_type == "FORWARD"
    error_message = "Forward rules must have rule_type FORWARD."
  }

  assert {
    condition     = length(aws_route53_resolver_rule_association.fwd) == 1
    error_message = "One rule association must be created per forward rule."
  }
}

run "dns_firewall_disabled" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    enable_dns_firewall       = false
  }

  assert {
    condition     = length(aws_route53_resolver_firewall_rule_group.this) == 0
    error_message = "No DNS Firewall rule group must be created when enable_dns_firewall is false."
  }

  assert {
    condition     = length(aws_route53_resolver_firewall_domain_list.blocked) == 0
    error_message = "No DNS Firewall block list must be created when enable_dns_firewall is false."
  }
}
