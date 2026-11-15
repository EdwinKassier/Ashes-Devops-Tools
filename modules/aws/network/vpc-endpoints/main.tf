# Centralized interface VPC endpoints + shared private hosted zones.
#
# In the SRA landing zone, interface endpoints (PrivateLink ENIs) for the common
# AWS control-plane services are created ONCE in the central network hub VPC and
# reached by spoke VPCs over the transit gateway. This avoids per-spoke endpoint
# sprawl and cost. Each endpoint policy is scoped to the organisation via the
# aws:PrincipalOrgID condition so only principals in var.org_id may use them.
#
# An endpoint's own private DNS is a hidden zone that only the endpoint VPC
# sees. With enable_shared_private_dns the module turns it off and serves each
# regional name (<service>.<region>.amazonaws.com) from a private hosted zone
# with an alias record to the endpoint. The zone ARNs (output
# shared_dns_zone_arns) go into a Route 53 Profile, and every VPC that
# associates the profile resolves the service names to the central endpoints.
#
# With security_group_ids empty and allowed_cidrs set, the module owns the
# endpoint security group (HTTPS from allowed_cidrs). Without any group the
# endpoints get the VPC default group, which the vpc module strips to deny-all.

resource "aws_security_group" "endpoints" {
  count = length(var.security_group_ids) == 0 && length(var.allowed_cidrs) > 0 ? 1 : 0

  name_prefix = "interface-endpoints-"
  description = "Centralized interface endpoints: HTTPS from allowed_cidrs."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS to the interface endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Attribute syntax: an empty list removes the AWS default allow-all egress
  # rule. The endpoints only answer requests (security groups are stateful).
  egress = []

  tags = merge(var.tags, { Name = "interface-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = !var.enable_shared_private_dns
  subnet_ids          = var.subnet_ids
  security_group_ids  = length(var.security_group_ids) > 0 ? var.security_group_ids : aws_security_group.endpoints[*].id

  # Endpoint policy. Default: allow only principals in this AWS Organization
  # (aws:PrincipalOrgID). Action="*" here relies on IAM for per-service authz and
  # keeps this shared hub endpoint service-agnostic; callers who want tighter,
  # per-service least-privilege pass a scoped policy via var.endpoint_policy_json.
  # endpoint_policy_mode = org_principals_and_resources also requires the
  # resource to belong to the organization (aws:ResourceOrgID), except on the
  # services in resource_org_exempt_services.
  policy = var.endpoint_policy_json != null ? var.endpoint_policy_json : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "*"
      Resource  = "*"
      Condition = {
        StringEquals = merge(
          { "aws:PrincipalOrgID" = var.org_id },
          var.endpoint_policy_mode == "org_principals_and_resources" && !contains(var.resource_org_exempt_services, each.value) ? { "aws:ResourceOrgID" = var.org_id } : {},
        )
      }
    }]
  })

  tags = var.tags
}

# Shared private hosted zone for split-horizon DNS of the centralized endpoints.
# Created only when a zone name is supplied.
resource "aws_route53_zone" "shared" {
  count = var.private_hosted_zone_name != "" ? 1 : 0

  name = var.private_hosted_zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags
}

locals {
  shared_dns_services = var.enable_shared_private_dns ? toset(var.interface_services) : toset([])
}

# One zone per service. depends_on: the endpoint must stop using its own
# private DNS before a zone with the same name is associated with the VPC (the
# two conflict while private_dns_enabled is true).
resource "aws_route53_zone" "endpoint" {
  for_each = local.shared_dns_services

  name    = "${each.key}.${var.region}.amazonaws.com"
  comment = "Central interface endpoint for ${each.key} (shared through the Route 53 Profile)."

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags

  depends_on = [aws_vpc_endpoint.interface]
}

resource "aws_route53_record" "endpoint" {
  # checkov:skip=CKV2_AWS_23:The alias target is the interface endpoint's own dns_entry, read through try(); Checkov's graph does not follow that attribute path.
  for_each = local.shared_dns_services

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = "${each.key}.${var.region}.amazonaws.com"
  type    = "A"

  # The real provider always returns at least one dns_entry for an interface
  # endpoint (the first is the regional name); try() only keeps mock plans
  # (empty computed lists) evaluable.
  alias {
    name                   = try(aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name, "")
    zone_id                = try(aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id, "")
    evaluate_target_health = false
  }
}
