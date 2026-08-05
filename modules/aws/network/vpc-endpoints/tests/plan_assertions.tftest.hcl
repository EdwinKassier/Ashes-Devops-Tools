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
