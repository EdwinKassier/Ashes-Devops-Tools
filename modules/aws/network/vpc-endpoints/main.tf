# Centralized interface VPC endpoints + shared private hosted zone.
#
# In the SRA landing zone, interface endpoints (PrivateLink ENIs) for the common
# AWS control-plane services are created ONCE in the central network hub VPC and
# reached by spoke VPCs over the transit gateway. This avoids per-spoke endpoint
# sprawl and cost. Each endpoint policy is scoped to the organisation via the
# aws:PrincipalOrgID condition so only principals in var.org_id may use them.
#
# For centralized-endpoint DNS to resolve from the spokes (split-horizon), the
# private DNS names must be served by a shared private hosted zone associated
# with each consuming VPC. This module manages that zone; cross-account VPC
# association (aws_route53_vpc_association_authorization + RAM) is an extension
# layered on by the network-hub stage and is intentionally out of scope here.

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids

  # Org-scoped endpoint policy: allow only principals in this AWS Organization.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "*"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = var.org_id
        }
      }
    }]
  })
}

# Shared private hosted zone for split-horizon DNS of the centralized endpoints.
# Created only when a zone name is supplied.
resource "aws_route53_zone" "shared" {
  count = var.private_hosted_zone_name != "" ? 1 : 0

  name = var.private_hosted_zone_name

  vpc {
    vpc_id = var.vpc_id
  }
}
