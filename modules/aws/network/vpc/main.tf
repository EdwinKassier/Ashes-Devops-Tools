# Data-driven VPC for the SRA landing zone.
#
# Subnets are NOT enumerated by a fixed role list. Instead the caller describes
# tiers in var.subnets (tier -> {newbits, number_offset, public}) and the module
# builds one subnet per tier per AZ, carving CIDRs from the VPC supernet with
# cidrsubnet().
#
# Routing ownership: the module OWNS one route table per tier per AZ (keyed
# "<tier>-<az_index>"), its subnet association, the optional internet gateway
# (+ the public tiers' default route to it), and any caller-declared static
# routes (var.routes, applied to every AZ table of a tier). Gateway endpoints
# (S3/DynamoDB) are associated with the non-public tiers' route tables. Targets
# the module does NOT own and that differ per AZ (e.g. stage-built NAT gateways)
# are layered on by the caller as aws_route resources against the
# route_table_ids_by_tier output, so route TABLES are never duplicated.
#
# IPAM vs cidrsubnet, resolved:
#   When ipam_pool_id is set, the VPC's real CIDR is allocated by IPAM and is
#   unknown at plan time, so cidrsubnet() on it would fail under mock_provider.
#   To keep subnet math deterministic and testable, local.vpc_cidr is ALWAYS
#   var.cidr_block. The caller therefore passes the intended CIDR (the same value
#   IPAM will allocate) even when ipam_pool_id drives the VPC allocation;
#   with ipam_allocation = "explicit_cidr" the VPC requests exactly that
#   cidr_block from the pool. cidr_block is always required for the subnet layout.

locals {
  vpc_cidr = var.cidr_block

  # AZs actually used, limited to az_count.
  azs = slice(var.availability_zones, 0, var.az_count)

  # Flatten (tier x az) into a single map keyed "tier-az". Each entry carries
  # the tier config plus the AZ index, used as the cidrsubnet netnum offset.
  subnet_defs = merge([
    for tier, cfg in var.subnets : {
      for i, az in local.azs :
      "${tier}-${az}" => {
        tier  = tier
        az    = az
        index = i
        cfg   = cfg
      }
    }
  ]...)

  # Route tables are keyed by AZ INDEX ("<tier>-<i>") rather than AZ name so the
  # address is stable (and statically addressable by `moved` blocks) regardless
  # of the caller's availability_zones list.
  route_table_defs = {
    for key, def in local.subnet_defs : "${def.tier}-${def.index}" => merge(def, { subnet_key = key })
  }

  public_tiers = [for tier, cfg in var.subnets : tier if try(cfg.public, false)]

  # Tiers whose route tables receive the gateway endpoints: caller-chosen, or by
  # default every non-public tier (private/isolated/tgw/...).
  gateway_endpoint_tiers = var.gateway_endpoint_tiers != null ? var.gateway_endpoint_tiers : [
    for tier, cfg in var.subnets : tier if !try(cfg.public, false)
  ]

  # Flatten (route table x caller route) into a map keyed
  # "<tier>-<i>|<destination>". Keys use only plan-known values (tier, index,
  # destination CIDR), so targets (e.g. a TGW id) may be apply-time unknown.
  static_routes = merge([
    for rt_key, def in local.route_table_defs : {
      for r in lookup(var.routes, def.tier, []) :
      "${rt_key}|${r.destination_cidr_block}" => merge(r, { rt_key = rt_key })
    }
  ]...)

  # (endpoint x route table) associations, keyed "<service>|<tier>-<i>".
  gateway_endpoint_associations = merge([
    for svc in var.gateway_endpoints : {
      for rt_key, def in local.route_table_defs :
      "${svc}|${rt_key}" => { service = svc, rt_key = rt_key }
      if contains(local.gateway_endpoint_tiers, def.tier)
    }
  ]...)
}

resource "aws_vpc" "this" {
  # Three shapes:
  #   * static (no pool)                 — cidr_block only.
  #   * IPAM, ipam_allocation = "netmask" (default, legacy) — pool +
  #     ipv4_netmask_length, cidr_block null. Existing IPAM VPCs keep this shape;
  #     changing the netmask attribute forces VPC replacement.
  #   * IPAM, ipam_allocation = "explicit_cidr" — pool + cidr_block, so the pool
  #     allocates exactly the block the subnet math assumes (provider rejects a
  #     netmask length alongside a CIDR). Opt-in for NEW VPCs only.
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" && var.ipam_allocation == "netmask" ? var.netmask_length : null
  cidr_block          = var.ipam_pool_id == "" || var.ipam_allocation == "explicit_cidr" ? var.cidr_block : null

  assign_generated_ipv6_cidr_block = var.enable_ipv6
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_subnet" "this" {
  for_each = local.subnet_defs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value.az
  cidr_block        = cidrsubnet(local.vpc_cidr, each.value.cfg.newbits, each.value.cfg.number_offset + each.value.index)

  # Auto-assigning public IPs is the intended behaviour of a tier explicitly
  # declared public = true (e.g. the public/ingress tier). Non-public tiers
  # leave this false, so only tiers the caller opts into as public get one.
  map_public_ip_on_launch = try(each.value.cfg.public, false) #tfsec:ignore:aws-ec2-no-public-ip-subnet - only tiers the caller explicitly opts into with public=true get a public IP; every other tier defaults to false

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.tier}-${each.value.az}"
    Tier = each.value.tier
  })
}

# Restrict the default security group to deny all traffic (tfsec/CIS): declaring
# the resource with no ingress/egress rules removes AWS's permissive defaults.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-default-deny" })
}

# VPC flow logs to the central log archive (tfsec aws-ec2-require-vpc-flow-logs).
resource "aws_flow_log" "this" {
  log_destination      = var.flow_log_destination_arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-flow-log" })
}

# Gateway endpoints (S3, DynamoDB) keep that traffic on the AWS backbone.
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoints)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}

resource "aws_vpc_endpoint_route_table_association" "gateway" {
  for_each = local.gateway_endpoint_associations

  vpc_endpoint_id = aws_vpc_endpoint.gateway[each.value.service].id
  route_table_id  = aws_route_table.this[each.value.rt_key].id
}

# ---------------------------------------------------------------------------
# Routing — one route table per tier per AZ
# ---------------------------------------------------------------------------

resource "aws_route_table" "this" {
  for_each = local.route_table_defs

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.tier}-${each.value.az}"
    Tier = each.value.tier
  })
}

resource "aws_route_table_association" "this" {
  for_each = local.route_table_defs

  subnet_id      = aws_subnet.this[each.value.subnet_key].id
  route_table_id = aws_route_table.this[each.key].id
}

# Optional internet gateway. When created, every public tier's route table gets a
# 0.0.0.0/0 default route to it (required for NAT gateways in a public tier).
resource "aws_internet_gateway" "this" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_route" "public_internet" {
  for_each = var.create_internet_gateway ? {
    for rt_key, def in local.route_table_defs : rt_key => def if contains(local.public_tiers, def.tier)
  } : {}

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

# Caller-declared static routes (var.routes), applied to every AZ table of a tier.
resource "aws_route" "this" {
  for_each = local.static_routes

  route_table_id            = aws_route_table.this[each.value.rt_key].id
  destination_cidr_block    = each.value.destination_cidr_block
  transit_gateway_id        = each.value.transit_gateway_id
  nat_gateway_id            = each.value.nat_gateway_id
  gateway_id                = each.value.gateway_id
  vpc_endpoint_id           = each.value.vpc_endpoint_id
  network_interface_id      = each.value.network_interface_id
  vpc_peering_connection_id = each.value.vpc_peering_connection_id
}
