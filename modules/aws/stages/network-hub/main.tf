# aws-network-hub stage (phase-2)
#
# Thin orchestration wrapper that builds the centralized network hub ENTIRELY in
# the NETWORK account. There is a SINGLE default `aws` provider (no aliases):
# every resource and child module runs in the same account/region.
#
# Composition:
#   - ipam                 — hierarchical IPAM, shared org-wide over RAM.
#   - inspection_vpc (vpc) — hosts the Network Firewall endpoints (firewall tier)
#                            and its transit-gateway attachment (tgw tier).
#   - egress_vpc (vpc)     — centralized egress: NAT (public tier), interface
#                            endpoints + resolver endpoints (private tier), and
#                            its transit-gateway attachment (tgw tier).
#   - stage-level NAT      — the vpc module owns route tables + the egress IGW;
#                            the stage adds one EIP + NAT gateway per egress
#                            public subnet and the per-AZ NAT / TGW routes into
#                            the module-owned route tables.
#   - transit_gateway      — segmented TGW; prod/nonprod default routes point at
#                            the inspection attachment so traffic is inspected.
#   - network_firewall     — stateful inspection in the inspection VPC.
#   - vpc_endpoints        — centralized interface endpoints in the egress VPC.
#   - route53_resolver     — inbound/outbound resolver + DNS firewall + Profile.
#   - network_access_analyzer — optional segmentation-intent scope.
#
# Subnet tier layout (newbits = 8 -> /24s carved from each /16; number_offset in
# units of one /24, spread over az_count AZs so tiers never overlap):
#   inspection VPC: firewall @0, tgw @8, private @16
#   egress VPC:     public   @0, tgw @8, private @16

locals {
  # /24 tiers, az_count subnets each. Offsets are multiples of 8 (> az_count max
  # of 3) so per-AZ subnets within a tier and across tiers never collide.
  inspection_subnets = {
    firewall = { newbits = 8, number_offset = 0 }
    tgw      = { newbits = 8, number_offset = 8 }
    private  = { newbits = 8, number_offset = 16 }
  }

  egress_subnets = {
    public  = { newbits = 8, number_offset = 0, public = true }
    tgw     = { newbits = 8, number_offset = 8 }
    private = { newbits = 8, number_offset = 16 }
  }

  # Centralized-inspection routing contract fed to the transit gateway. The
  # prod & nonprod default routes point at the inspection attachment so all
  # egress/east-west traffic is forced through the firewall. Extracted to a
  # local so the wiring is assertable independently of the (override_module'd)
  # transit_gateway child.
  tgw_propagations = {
    "inspection->prod"    = { attachment = "inspection", route_table = "prod" }
    "inspection->nonprod" = { attachment = "inspection", route_table = "nonprod" }
    "egress->shared"      = { attachment = "egress", route_table = "shared" }
  }

  tgw_routes = {
    "prod:default"    = { route_table = "prod", cidr = "0.0.0.0/0", attachment = "inspection" }
    "nonprod:default" = { route_table = "nonprod", cidr = "0.0.0.0/0", attachment = "inspection" }
  }
}

# ---------------------------------------------------------------------------
# IPAM — hierarchical pools shared org-wide
# ---------------------------------------------------------------------------

module "ipam" {
  source = "../../network/ipam"

  aws_enabled_regions = var.aws_enabled_regions
  top_cidr            = var.top_cidr
  regional_cidrs      = var.regional_cidrs
  org_arn             = var.org_arn

  tags = var.tags
}

locals {
  # Hub VPCs allocate their (explicit) CIDR from the regional IPAM pool only when
  # opted in. Adding ipv4_ipam_pool_id to an existing static VPC forces
  # replacement, so with ipam_mode_for_new_vpcs_only (default) only the VPCs named
  # in ipam_new_vpcs move; every other keeps today's static attributes.
  hub_regional_pool_id = try(module.ipam.regional_pool_ids[var.aws_region], "")
  hub_vpc_ipam_pool_ids = {
    for name in ["inspection", "egress"] :
    name => (!var.ipam_mode_for_new_vpcs_only || contains(var.ipam_new_vpcs, name)) ? local.hub_regional_pool_id : ""
  }
}

# ---------------------------------------------------------------------------
# Inspection VPC — hosts the Network Firewall + its TGW attachment
# ---------------------------------------------------------------------------

module "inspection_vpc" {
  source = "../../network/vpc"

  name                     = "inspection"
  cidr_block               = var.inspection_cidr
  ipam_pool_id             = local.hub_vpc_ipam_pool_ids["inspection"]
  ipam_allocation          = "explicit_cidr"
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = local.inspection_subnets
  flow_log_destination_arn = var.flow_log_destination_arn
  gateway_endpoints        = []
  tags                     = var.tags
}

# ---------------------------------------------------------------------------
# Egress VPC — centralized NAT egress, interface endpoints, resolver endpoints
# ---------------------------------------------------------------------------

module "egress_vpc" {
  source = "../../network/vpc"

  name                     = "egress"
  cidr_block               = var.egress_cidr
  ipam_pool_id             = local.hub_vpc_ipam_pool_ids["egress"]
  ipam_allocation          = "explicit_cidr"
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = local.egress_subnets
  flow_log_destination_arn = var.flow_log_destination_arn
  gateway_endpoints        = []
  tags                     = var.tags

  # The NAT gateways live in the public tier and need an IGW; the module adds
  # the public tier's 0.0.0.0/0 -> IGW route.
  create_internet_gateway = true
}

# ---------------------------------------------------------------------------
# Stage-level NAT + routes for the hub VPCs
#
# The vpc module OWNS every route table (one per tier per AZ), its subnet
# associations, the egress IGW and the public-tier default route to it. The
# stage only layers on routes whose targets it owns and that differ per AZ: one
# Elastic IP + NAT gateway per egress public subnet, and the per-AZ routes to
# NAT / the transit gateway. Route tables are looked up from the vpc module's
# route_table_ids_by_tier output (index i == AZ i), so no table is duplicated.
# ---------------------------------------------------------------------------

locals {
  # Key NAT resources off the STATIC AZ index (0..az_count-1) rather than the
  # computed subnet ids: the ids are unknown at plan under mock, and a for_each
  # over an unknown-valued set is rejected. The subnet id is looked up as the
  # value, so only the value (not the key set) is apply-time.
  nat_az_indexes                 = range(var.az_count)
  nat_az_keys                    = toset([for i in local.nat_az_indexes : tostring(i)])
  egress_public_subnet_ids       = module.egress_vpc.subnet_ids_by_tier["public"]
  egress_private_route_table_ids = module.egress_vpc.route_table_ids_by_tier["private"]
  egress_tgw_route_table_ids     = module.egress_vpc.route_table_ids_by_tier["tgw"]

  # Return / hand-off routes into the transit gateway, keyed "<vpc>-<tier>-<i>":
  #   - egress public + private tiers -> top_cidr via TGW (return path to spokes
  #     for NAT'd flows, interface endpoints and resolver endpoints).
  #   - inspection firewall tier -> 0.0.0.0/0 via TGW (inspected traffic goes back
  #     to the TGW, whose inspection route table forwards it on).
  hub_tgw_routes = merge(
    {
      for pair in setproduct(["public", "private"], local.nat_az_indexes) :
      "egress-${pair[0]}-${pair[1]}" => {
        route_table_id = module.egress_vpc.route_table_ids_by_tier[pair[0]][pair[1]]
        destination    = var.top_cidr
      }
    },
    {
      for i in local.nat_az_indexes :
      "inspection-firewall-${i}" => {
        route_table_id = module.inspection_vpc.route_table_ids_by_tier["firewall"][i]
        destination    = "0.0.0.0/0"
      }
    },
  )
}

resource "aws_eip" "nat" {
  for_each = local.nat_az_keys

  domain = "vpc"

  tags = merge(var.tags, { Name = "egress-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_az_keys

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = local.egress_public_subnet_ids[tonumber(each.key)]

  tags = merge(var.tags, { Name = "egress-nat-${each.key}" })

  depends_on = [module.egress_vpc]
}

# Each AZ's private default route egresses through the NAT gateway in the SAME
# AZ. This gives true per-AZ high availability (a NAT or AZ failure is contained
# to that AZ) and avoids cross-AZ NAT data charges. With az_count = 1 this
# collapses to a single route table and NAT (FinOps F3).
resource "aws_route" "egress_default" {
  for_each = local.nat_az_keys

  route_table_id         = local.egress_private_route_table_ids[tonumber(each.key)]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

# Spoke internet-bound traffic arrives from the TGW into the egress tgw tier and
# must leave via the SAME-AZ NAT gateway.
resource "aws_route" "egress_tgw_default" {
  for_each = local.nat_az_keys

  route_table_id         = local.egress_tgw_route_table_ids[tonumber(each.key)]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

# Centralized inspection: traffic the TGW hands to the inspection VPC lands in the
# tgw tier and must be sent to the Network Firewall endpoint in the SAME AZ (the
# inspection attachment runs in appliance mode, so flows stay symmetric). The
# firewall tier then returns inspected traffic to the TGW (hub_to_tgw above).
# Without these routes the tgw tier has no default route and inspected traffic
# is black-holed / never reaches the firewall.
resource "aws_route" "inspection_tgw_to_firewall" {
  for_each = var.enable_network_firewall ? local.nat_az_keys : toset([])

  route_table_id         = module.inspection_vpc.route_table_ids_by_tier["tgw"][tonumber(each.key)]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = module.network_firewall.firewall_endpoint_ids_by_az[var.availability_zones[tonumber(each.key)]]
}

resource "aws_route" "hub_to_tgw" {
  for_each = local.hub_tgw_routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination
  transit_gateway_id     = module.transit_gateway.tgw_id

  # A VPC route to a TGW is only accepted once the VPC is attached to it.
  depends_on = [module.transit_gateway]
}

# The per-AZ egress private route tables + associations used to be stage-owned;
# they now live in the vpc module (keyed "<tier>-<az_index>"). These moved blocks
# carry existing state across without destroying the tables (az_count <= 3).
moved {
  from = aws_route_table.egress_private["0"]
  to   = module.egress_vpc.aws_route_table.this["private-0"]
}

moved {
  from = aws_route_table.egress_private["1"]
  to   = module.egress_vpc.aws_route_table.this["private-1"]
}

moved {
  from = aws_route_table.egress_private["2"]
  to   = module.egress_vpc.aws_route_table.this["private-2"]
}

moved {
  from = aws_route_table_association.egress_private["0"]
  to   = module.egress_vpc.aws_route_table_association.this["private-0"]
}

moved {
  from = aws_route_table_association.egress_private["1"]
  to   = module.egress_vpc.aws_route_table_association.this["private-1"]
}

moved {
  from = aws_route_table_association.egress_private["2"]
  to   = module.egress_vpc.aws_route_table_association.this["private-2"]
}

# ---------------------------------------------------------------------------
# Transit gateway — segmented hub; default routes forced through inspection
# ---------------------------------------------------------------------------

module "transit_gateway" {
  source = "../../network/transit-gateway"

  org_arn = var.org_arn

  route_tables = ["prod", "nonprod", "inspection", "shared"]

  attachments = {
    inspection = {
      vpc_id         = module.inspection_vpc.vpc_id
      subnet_ids     = module.inspection_vpc.subnet_ids_by_tier["tgw"]
      segment        = "inspection"
      appliance_mode = true
    }
    egress = {
      vpc_id     = module.egress_vpc.vpc_id
      subnet_ids = module.egress_vpc.subnet_ids_by_tier["tgw"]
      segment    = "shared"
    }
  }

  # Inspection attachment propagates into prod & nonprod so their default route
  # (below) resolves to the firewall. Egress propagates into shared.
  propagations = local.tgw_propagations

  # Centralized inspection: prod & nonprod default routes point at the
  # inspection attachment so all egress/east-west traffic is inspected.
  routes = local.tgw_routes

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Site-to-Site VPN — opt-in hybrid connectivity terminating on the TGW
#
# The TGW has default association/propagation disabled (segmentation), so the
# VPN attachment is associated with one segment and propagates its on-premises
# routes into the listed segments explicitly.
# ---------------------------------------------------------------------------

module "vpn" {
  source = "../../network/vpn"
  count  = var.enable_vpn ? 1 : 0

  name                     = "hub"
  customer_gateway_ip      = var.vpn.customer_gateway_ip
  customer_gateway_bgp_asn = var.vpn.customer_gateway_bgp_asn
  attach_to                = "transit_gateway"
  transit_gateway_id       = module.transit_gateway.tgw_id
  static_routes_only       = var.vpn.static_routes_only
  tunnel_inside_cidrs      = var.vpn.tunnel_inside_cidrs
  enable_acceleration      = var.vpn.enable_acceleration
  tags                     = var.tags
}

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  count = var.enable_vpn ? 1 : 0

  transit_gateway_attachment_id  = module.vpn[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[var.vpn.route_table]
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpn" {
  for_each = var.enable_vpn ? toset(var.vpn.propagate_to) : toset([])

  transit_gateway_attachment_id  = module.vpn[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[each.key]
}

# ---------------------------------------------------------------------------
# Network Firewall — stateful inspection in the inspection VPC
# ---------------------------------------------------------------------------

module "network_firewall" {
  source = "../../network/network-firewall"

  enable_network_firewall = var.enable_network_firewall
  inspection_vpc_id       = module.inspection_vpc.vpc_id
  firewall_subnet_ids     = module.inspection_vpc.subnet_ids_by_tier["firewall"]
  log_bucket_name         = var.log_bucket_name
  region                  = var.aws_region

  # STRICT_ORDER baseline: AWS-managed threat groups, optional custom rules and
  # egress allowlist, log-but-pass default until allow rules are in place.
  # HOME_NET = the org supernet so rules match spoke traffic, not just the
  # inspection VPC's own CIDR.
  managed_rule_groups      = var.network_firewall_managed_rule_groups
  stateful_default_actions = var.network_firewall_stateful_default_actions
  egress_domain_allowlist  = var.network_firewall_egress_domain_allowlist
  suricata_rules           = var.network_firewall_suricata_rules
  home_net_cidrs           = [var.top_cidr]

  tags = var.tags
}

# Production egress fails closed: an enforced estate must drop unmatched
# established traffic and carry a domain allowlist, or carry the waiver.
resource "terraform_data" "production_egress_enforced" {
  input = var.enforce_egress_allowlist

  lifecycle {
    precondition {
      condition = (
        !var.enforce_egress_allowlist || var.egress_alert_only_waived ||
        (contains(var.network_firewall_stateful_default_actions, "aws:drop_established") &&
        length(var.network_firewall_egress_domain_allowlist) > 0)
      )
      error_message = "Production egress must fail closed: set network_firewall_stateful_default_actions to include aws:drop_established AND a non-empty network_firewall_egress_domain_allowlist (config aws.network.stateful_default_actions / aws.network.egress_domain_allowlist), or explicitly waive with egress_alert_only_waived (config aws.network.egress_alert_only_waived: true)."
    }
  }
}

# ---------------------------------------------------------------------------
# Centralized VPC endpoints — interface endpoints in the egress VPC
# ---------------------------------------------------------------------------

module "vpc_endpoints" {
  source = "../../network/vpc-endpoints"

  vpc_id                   = module.egress_vpc.vpc_id
  region                   = var.aws_region
  subnet_ids               = module.egress_vpc.subnet_ids_by_tier["private"]
  org_id                   = var.org_id
  private_hosted_zone_name = var.private_hosted_zone_name

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Route 53 resolver + DNS firewall — associated with the egress VPC
# ---------------------------------------------------------------------------

module "route53_resolver" {
  source = "../../network/route53-resolver"

  vpc_id                    = module.egress_vpc.vpc_id
  subnet_ids                = module.egress_vpc.subnet_ids_by_tier["private"]
  org_arn                   = var.org_arn
  query_log_destination_arn = var.flow_log_destination_arn
  enable_dns_firewall       = true

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Network Access Analyzer — optional segmentation-intent scope
# ---------------------------------------------------------------------------

module "network_access_analyzer" {
  source = "../../network/network-access-analyzer"

  enable_network_access_analyzer = var.enable_network_access_analyzer

  tags = var.tags
}
