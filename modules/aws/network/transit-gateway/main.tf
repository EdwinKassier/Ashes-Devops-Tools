# Segmented transit gateway hub for the SRA landing zone.
#
# The gateway itself disables the default association/propagation route tables
# (default_route_table_association / _propagation = "disable"). Segmentation is
# expressed explicitly instead:
#
#   - One route table per segment (var.route_tables: prod, nonprod, inspection,
#     shared). Each VPC attachment is ASSOCIATED with exactly one segment's
#     route table (var.attachments[*].segment).
#   - Reachability between segments is granted ONLY by explicit propagations
#     (var.propagations). prod<->nonprod isolation is enforced by OMITTING any
#     prod->nonprod or nonprod->prod propagation: prod and nonprod each only
#     propagate to/from shared, never to each other. There is no default route
#     table to leak reachability, so "absent propagation" == "no route".
#   - Default routes (var.routes) steer segment traffic to the inspection
#     attachment or blackhole it, driven by plan-known string keys.
#
# All for_each keys (route table names, attachment names, propagation/route map
# keys) are static strings so the plan graph is fully known under mock_provider.

resource "aws_ec2_transit_gateway" "this" {
  description = var.description

  # Disable the implicit default route tables so all association/propagation is
  # explicit and segment isolation cannot be bypassed by a default table.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = { Name = var.description }
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = toset(var.route_tables)

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = each.value }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.attachments

  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  vpc_id                 = each.value.vpc_id
  subnet_ids             = each.value.subnet_ids
  appliance_mode_support = try(each.value.appliance_mode, false) ? "enable" : "disable"

  # Association/propagation are managed by the dedicated resources below so the
  # segment wiring is explicit; never fall back to the (disabled) default table.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.segment].id
}

# Explicit propagations only. The map is keyed by plan-known strings such as
# "prod:shared" so the graph is static. prod<->nonprod pairings are deliberately
# absent, which is what enforces prod/nonprod isolation (no default table).
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.propagations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

# Static routes: steer a segment's default route to the inspection attachment,
# or blackhole a destination. attachment is null for blackhole routes.
resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
  transit_gateway_attachment_id  = try(each.value.attachment, null) != null ? aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id : null
  blackhole                      = try(each.value.blackhole, false)
}

# Share the TGW across the organization via RAM. External principals are
# disallowed; the org principal is granted access.
resource "aws_ram_resource_share" "this" {
  name                      = var.share_name
  allow_external_principals = false
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = var.org_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}
