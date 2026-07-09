# Hierarchical AWS VPC IP Address Manager (IPAM) for the SRA landing zone.
#
# Builds a two-tier IPAM pool topology in the private default scope:
#   - a single top-level pool that owns the whole supernet (var.top_cidr), and
#   - one regional pool per enabled region, sourced from the top pool, that
#     carves a per-region CIDR (var.regional_cidrs) out of that supernet.
#
# The regional pools are shared organization-wide via AWS RAM so member accounts
# can allocate VPC CIDRs from centrally governed address space. In practice this
# module is deployed in (and IPAM administration is delegated to) the network
# account; the RAM principal association targets the organization ARN so every
# account in the org can consume the shared pools.

resource "aws_vpc_ipam" "this" {
  description = var.description

  dynamic "operating_regions" {
    for_each = toset(var.aws_enabled_regions)
    content {
      region_name = operating_regions.value
    }
  }
}

# Top-level pool: owns the full supernet. A top pool has no locale (it is not
# pinned to a single region); regional child pools carry the locale instead.
resource "aws_vpc_ipam_pool" "top" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  locale         = null
  description    = "Top-level IPAM pool owning the ${var.top_cidr} supernet."
}

resource "aws_vpc_ipam_pool_cidr" "top" {
  ipam_pool_id = aws_vpc_ipam_pool.top.id
  cidr         = var.top_cidr
}

# Regional pools: one per enabled region, sourced from the top pool. The locale
# ties each pool to a region so VPCs in that region can allocate from it.
resource "aws_vpc_ipam_pool" "regional" {
  for_each = toset(var.aws_enabled_regions)

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  locale              = each.value
  source_ipam_pool_id = aws_vpc_ipam_pool.top.id
  description         = "Regional IPAM pool for ${each.value}."
}

# Each regional pool provisions its slice of the supernet.
resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = var.regional_cidrs

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.key].id
  cidr         = each.value
}

# RAM share the regional pools organization-wide. allow_external_principals is
# false: sharing is scoped to the organization only, never to external accounts.
resource "aws_ram_resource_share" "this" {
  name                      = var.share_name
  allow_external_principals = false
}

resource "aws_ram_resource_association" "pools" {
  for_each = aws_vpc_ipam_pool.regional

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = var.org_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}
