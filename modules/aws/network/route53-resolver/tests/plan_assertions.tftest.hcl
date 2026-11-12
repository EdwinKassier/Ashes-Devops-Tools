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
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10"]
  }

  assert {
    condition     = aws_route53_resolver_endpoint.inbound[0].direction == "INBOUND"
    error_message = "Inbound resolver endpoint must have direction INBOUND."
  }

  assert {
    condition     = aws_route53_resolver_endpoint.outbound[0].direction == "OUTBOUND"
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
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10"]
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

run "module_tags_applied" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10"]
    tags                      = { Owner = "test" }
  }

  assert {
    condition     = aws_route53_resolver_endpoint.inbound[0].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_route53_resolver_endpoint.inbound"
  }
}

run "profile_carries_dns_settings_not_a_vpc" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    profile_hosted_zone_arns  = { ssm = "arn:aws:route53:::hostedzone/Z0000000000000000001" }
  }

  assert {
    condition     = length(aws_route53profiles_resource_association.firewall) == 1 && jsondecode(aws_route53profiles_resource_association.firewall[0].resource_properties).priority == 101
    error_message = "The DNS Firewall rule group must ride the profile (with a priority) so every spoke that associates the profile is filtered."
  }

  assert {
    condition     = aws_route53profiles_resource_association.hosted_zones["ssm"].resource_arn == "arn:aws:route53:::hostedzone/Z0000000000000000001"
    error_message = "Each shared private hosted zone must be a profile resource."
  }

  assert {
    condition     = !anytrue([for r in values(aws_route53profiles_resource_association.hosted_zones) : strcontains(r.resource_arn, ":vpc/")])
    error_message = "A VPC is not a valid profile resource; VPCs join a profile through aws_route53profiles_association."
  }
}

run "forward_rules_ride_the_profile" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10"]
    forward_rules             = { corp = { domain_name = "corp.example.", target_ips = ["192.168.0.10"] } }
  }

  assert {
    condition     = length(aws_route53profiles_resource_association.rules) == 1 && aws_route53profiles_resource_association.rules["corp"].name == "org-profile-rule-corp"
    error_message = "Each forward rule must also be a profile resource, so spokes that associate the profile forward the domain."
  }

  assert {
    condition     = length(aws_security_group.resolver[0].egress) == 2 && alltrue([for r in aws_security_group.resolver[0].egress : r.from_port == 53 && toset(r.cidr_blocks) == toset(["192.168.0.10/32"])])
    error_message = "Resolver egress must be DNS to the forward target IPs only, not 0.0.0.0/0."
  }
}

run "resolver_endpoints_are_opt_in" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.inbound) == 0 && length(aws_route53_resolver_endpoint.outbound) == 0 && length(aws_security_group.resolver) == 0
    error_message = "Resolver endpoints (about USD 365 per month) must not exist unless enabled (ARC-21)."
  }

  assert {
    condition     = output.inbound_endpoint_id == null && output.outbound_endpoint_id == null && length(output.inbound_endpoint_ips) == 0
    error_message = "With the endpoints off, the endpoint outputs must be null (IDs) and empty (IPs)."
  }
}

run "enabled_endpoints_get_a_dns_security_group" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10", "192.168.0.0/16"]
  }

  assert {
    condition = (
      length(aws_route53_resolver_endpoint.inbound) == 1 &&
      length(aws_security_group.resolver) == 1 &&
      alltrue([for r in aws_security_group.resolver[0].ingress : r.from_port == 53 && r.to_port == 53 && toset(r.cidr_blocks) == toset(["10.64.0.0/10", "192.168.0.0/16"])]) &&
      length(aws_security_group.resolver[0].ingress) == 2
    )
    error_message = "Enabled endpoints need a module-owned security group that admits DNS (TCP and UDP 53) from allowed_cidrs only."
  }

  assert {
    condition     = toset([for r in aws_security_group.resolver[0].ingress : r.protocol]) == toset(["tcp", "udp"])
    error_message = "The resolver security group must admit DNS over both TCP and UDP."
  }

  assert {
    condition     = length(aws_security_group.resolver[0].egress) == 0
    error_message = "With no forward rules the resolver security group needs no egress rule (replies are stateful)."
  }
}

run "caller_security_groups_replace_the_module_group" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    security_group_ids        = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_security_group.resolver) == 0 && aws_route53_resolver_endpoint.inbound[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Caller security groups must be used as given, with no module-owned group."
  }
}
