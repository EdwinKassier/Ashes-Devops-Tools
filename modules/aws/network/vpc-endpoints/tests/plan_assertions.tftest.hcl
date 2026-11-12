# Resource-assertion tests for the aws/vpc-endpoints module.
#
# Asserts on configured attributes and for_each-derived counts known at plan
# time under mock_provider. The endpoint policy is jsonencode()'d locally, so
# it is fully known at plan time and can be regex-checked.

mock_provider "aws" {}

run "endpoints_and_policy_configured" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    region = "eu-west-2"
    org_id = "o-abcde12345"
  }

  # One endpoint per requested service.
  assert {
    condition     = length(aws_vpc_endpoint.interface) == length(var.interface_services)
    error_message = "One interface endpoint must be created per service in interface_services."
  }

  # Non-vacuous: defaults request 7 services.
  assert {
    condition     = length(aws_vpc_endpoint.interface) == 7
    error_message = "Default interface_services must produce exactly 7 endpoints."
  }

  # Endpoint policy must be org-scoped via aws:PrincipalOrgID.
  assert {
    condition     = can(regex("aws:PrincipalOrgID", aws_vpc_endpoint.interface["ssm"].policy))
    error_message = "Endpoint policy must scope access with the aws:PrincipalOrgID condition."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].vpc_endpoint_type == "Interface"
    error_message = "Endpoints must be of type Interface."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].private_dns_enabled == true
    error_message = "Private DNS must be enabled on interface endpoints."
  }

  # No zone name supplied -> no private hosted zone created.
  assert {
    condition     = length(aws_route53_zone.shared) == 0
    error_message = "No private hosted zone must be created when private_hosted_zone_name is empty."
  }
}

run "shared_phz_created_when_named" {
  command = plan

  variables {
    vpc_id                   = "vpc-0123456789abcdef0"
    region                   = "eu-west-2"
    org_id                   = "o-abcde12345"
    private_hosted_zone_name = "internal.example.com"
  }

  assert {
    condition     = length(aws_route53_zone.shared) == 1
    error_message = "A private hosted zone must be created when private_hosted_zone_name is set."
  }

  assert {
    condition     = aws_route53_zone.shared[0].name == "internal.example.com"
    error_message = "Private hosted zone name must match private_hosted_zone_name."
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    region = "eu-west-2"
    org_id = "o-abcde12345"
    tags   = { Owner = "test" }
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_vpc_endpoint.interface"
  }
}

run "shared_private_dns_serves_other_vpcs" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    region                    = "eu-west-2"
    org_id                    = "o-abc1234567"
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    interface_services        = ["ssm", "sts"]
    allowed_cidrs             = ["10.64.0.0/10"]
    enable_shared_private_dns = true
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : !e.private_dns_enabled])
    error_message = "Shared endpoints must not use the hidden per-VPC private DNS zone; their names come from shareable private hosted zones."
  }

  assert {
    condition     = aws_route53_zone.endpoint["ssm"].name == "ssm.eu-west-2.amazonaws.com" && aws_route53_record.endpoint["sts"].name == "sts.eu-west-2.amazonaws.com" && aws_route53_record.endpoint["sts"].type == "A"
    error_message = "Each service needs a private hosted zone for its regional name with an alias A record to the endpoint."
  }

  assert {
    condition     = length(aws_security_group.endpoints) == 1 && length(aws_security_group.endpoints[0].ingress) == 1 && alltrue([for r in aws_security_group.endpoints[0].ingress : r.from_port == 443 && r.to_port == 443 && r.protocol == "tcp" && toset(r.cidr_blocks) == toset(["10.64.0.0/10"])])
    error_message = "The endpoints need a security group that admits HTTPS from allowed_cidrs; the VPC default group denies everything."
  }

  assert {
    condition     = length(aws_security_group.endpoints[0].egress) == 0
    error_message = "The endpoint security group needs no egress rule (security groups are stateful)."
  }

  assert {
    condition     = toset(keys(output.shared_dns_zone_arns)) == toset(["ssm", "sts"])
    error_message = "The zone ARNs must be exported keyed by service, for the Route 53 Profile."
  }
}

run "private_dns_stays_on_by_default" {
  command = plan

  variables {
    vpc_id             = "vpc-0123456789abcdef0"
    region             = "eu-west-2"
    org_id             = "o-abc1234567"
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled]) && length(aws_route53_zone.endpoint) == 0 && length(output.shared_dns_zone_arns) == 0
    error_message = "Without enable_shared_private_dns the endpoints keep their own private DNS and no service zones are created."
  }

  assert {
    condition     = length(aws_security_group.endpoints) == 0 && aws_vpc_endpoint.interface["ssm"].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Caller security groups must be used as given, with no module-owned group."
  }
}
