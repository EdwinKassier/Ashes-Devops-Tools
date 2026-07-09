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
#   - stage-level NAT      — the vpc module intentionally omits NAT; the stage
#                            adds one EIP + NAT gateway per egress public subnet
#                            and a private route table default route to it.
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
}

# ---------------------------------------------------------------------------
# IPAM — hierarchical pools shared org-wide
# ---------------------------------------------------------------------------

module "ipam" {
  source = "../../aws/ipam"

  aws_enabled_regions = var.aws_enabled_regions
  top_cidr            = var.top_cidr
  regional_cidrs      = var.regional_cidrs
  org_arn             = var.org_arn
}

# ---------------------------------------------------------------------------
# Inspection VPC — hosts the Network Firewall + its TGW attachment
# ---------------------------------------------------------------------------

module "inspection_vpc" {
  source = "../../aws/vpc"

  name                     = "inspection"
  cidr_block               = var.inspection_cidr
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = local.inspection_subnets
  flow_log_destination_arn = var.flow_log_destination_arn
  gateway_endpoints        = []
}

# ---------------------------------------------------------------------------
# Egress VPC — centralized NAT egress, interface endpoints, resolver endpoints
# ---------------------------------------------------------------------------

module "egress_vpc" {
  source = "../../aws/vpc"

  name                     = "egress"
  cidr_block               = var.egress_cidr
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = local.egress_subnets
  flow_log_destination_arn = var.flow_log_destination_arn
  gateway_endpoints        = []
}

# ---------------------------------------------------------------------------
# Stage-level NAT for the egress VPC
#
# The vpc leaf module intentionally omits NAT, so the stage layers it on: one
# Elastic IP + NAT gateway per egress public subnet, plus a single private route
# table whose default route egresses through the first NAT gateway. Wiring uses
# the egress VPC's `public` tier subnet ids (a plan-known-length list under real
# apply; the tests override_module the vpc children where the ids are unknown).
# ---------------------------------------------------------------------------

locals {
  # Key NAT resources off the STATIC AZ index (0..az_count-1) rather than the
  # computed subnet ids: the ids are unknown at plan under mock, and a for_each
  # over an unknown-valued set is rejected. The subnet id is looked up as the
  # value, so only the value (not the key set) is apply-time.
  nat_az_indexes            = range(var.az_count)
  egress_public_subnet_ids  = module.egress_vpc.subnet_ids_by_tier["public"]
  egress_private_subnet_ids = module.egress_vpc.subnet_ids_by_tier["private"]
}

resource "aws_eip" "nat" {
  for_each = toset([for i in local.nat_az_indexes : tostring(i)])

  domain = "vpc"

  tags = { Name = "egress-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = toset([for i in local.nat_az_indexes : tostring(i)])

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = local.egress_public_subnet_ids[tonumber(each.key)]

  tags = { Name = "egress-nat-${each.key}" }

  depends_on = [module.egress_vpc]
}

# One private route table for the egress private tier; default route egresses
# through the first NAT gateway (single-NAT keeps the stage simple; make it
# per-AZ by keying the route table off private subnets if HA egress is needed).
resource "aws_route_table" "egress_private" {
  vpc_id = module.egress_vpc.vpc_id

  tags = { Name = "egress-private" }
}

resource "aws_route" "egress_default" {
  route_table_id         = aws_route_table.egress_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = values(aws_nat_gateway.this)[0].id
}

resource "aws_route_table_association" "egress_private" {
  for_each = toset([for i in local.nat_az_indexes : tostring(i)])

  subnet_id      = local.egress_private_subnet_ids[tonumber(each.key)]
  route_table_id = aws_route_table.egress_private.id
}

# ---------------------------------------------------------------------------
# Transit gateway — segmented hub; default routes forced through inspection
# ---------------------------------------------------------------------------

module "transit_gateway" {
  source = "../../aws/transit-gateway"

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
  propagations = {
    "inspection->prod"    = { attachment = "inspection", route_table = "prod" }
    "inspection->nonprod" = { attachment = "inspection", route_table = "nonprod" }
    "egress->shared"      = { attachment = "egress", route_table = "shared" }
  }

  # Centralized inspection: prod & nonprod default routes point at the
  # inspection attachment so all egress/east-west traffic is inspected.
  routes = {
    "prod:default"    = { route_table = "prod", cidr = "0.0.0.0/0", attachment = "inspection" }
    "nonprod:default" = { route_table = "nonprod", cidr = "0.0.0.0/0", attachment = "inspection" }
  }
}

# ---------------------------------------------------------------------------
# Network Firewall — stateful inspection in the inspection VPC
# ---------------------------------------------------------------------------

module "network_firewall" {
  source = "../../aws/network-firewall"

  enable_network_firewall = var.enable_network_firewall
  inspection_vpc_id       = module.inspection_vpc.vpc_id
  firewall_subnet_ids     = module.inspection_vpc.subnet_ids_by_tier["firewall"]
  log_bucket_name         = var.log_bucket_name
}

# ---------------------------------------------------------------------------
# Centralized VPC endpoints — interface endpoints in the egress VPC
# ---------------------------------------------------------------------------

module "vpc_endpoints" {
  source = "../../aws/vpc-endpoints"

  vpc_id                   = module.egress_vpc.vpc_id
  region                   = var.aws_region
  subnet_ids               = module.egress_vpc.subnet_ids_by_tier["private"]
  org_id                   = var.org_id
  private_hosted_zone_name = var.private_hosted_zone_name
}

# ---------------------------------------------------------------------------
# Route 53 resolver + DNS firewall — associated with the egress VPC
# ---------------------------------------------------------------------------

module "route53_resolver" {
  source = "../../aws/route53-resolver"

  vpc_id                    = module.egress_vpc.vpc_id
  subnet_ids                = module.egress_vpc.subnet_ids_by_tier["private"]
  org_arn                   = var.org_arn
  query_log_destination_arn = var.flow_log_destination_arn
  enable_dns_firewall       = true
}

# ---------------------------------------------------------------------------
# Network Access Analyzer — optional segmentation-intent scope
# ---------------------------------------------------------------------------

module "network_access_analyzer" {
  source = "../../aws/network-access-analyzer"

  enable_network_access_analyzer = var.enable_network_access_analyzer
}
