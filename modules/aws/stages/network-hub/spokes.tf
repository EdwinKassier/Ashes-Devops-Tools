# ---------------------------------------------------------------------------
# Workload spoke routing (var.spoke_attachments)
#
# A spoke attachment is created in the WORKLOAD account (modules/aws/stages/
# workload) with default association/propagation off, because only the TGW
# owner (this, the network account) can accept it and wire it into the segment
# route tables. The workload cannot reach them, so the attachment IDs come in
# as an explicit, plan-known map (aws.network.spoke_attachments, filled from
# each aws-workload-<env> output tgw_attachment_id after its first apply).
#
# Per spoke:
#   - accept the cross-account attachment (the TGW does not auto-accept);
#   - associate it with its segment table (prod / nonprod), whose 0.0.0.0/0
#     points at the inspection attachment, so everything it sends is inspected;
#   - propagate its CIDR into the inspection table, so inspected traffic
#     (east-west, egress replies, on-premises via the hybrid table) can reach it;
#   - with a cidr, blackhole it in the other segment's table (segment isolation
#     at the end of this file).
#
# Without the Network Firewall (the starter profile) the inspection VPC
# forwards nothing, so the segment tables default-route to the egress
# attachment instead and each spoke propagates into the shared table, which
# the egress attachment uses for the NAT replies. Starter egress is NAT only,
# not inspected (D4).
#
# Hub routes the inspected spokes need (spoke_hub_routes in main.tf, only with
# the firewall and at least one spoke wired, so an estate without spokes plans
# no change):
#   - inspection 0.0.0.0/0 -> egress attachment: inspected internet-bound
#     traffic reaches the NAT gateways;
#   - shared top_cidr -> inspection attachment: NAT replies (egress is in the
#     shared segment) go back through the firewall to the spoke, so egress is
#     inspected both ways (the inspection attachment runs in appliance mode).
# ---------------------------------------------------------------------------

# Destroying an accepter deletes the attachment itself. Never flip `accept` on a
# managed spoke, and move (not rename) a key with a `moved` block.
resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spoke" {
  for_each = { for k, s in var.spoke_attachments : k => s if s.accept }

  transit_gateway_attachment_id = each.value.attachment_id

  # The TGW has no default route tables; association/propagation are explicit below.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "spoke-${each.key}" })
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = var.spoke_attachments

  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[each.value.segment]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spoke]
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  for_each = var.spoke_attachments

  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[local.spoke_return_route_table]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spoke]
}

# Segment isolation (ARC-11). Both segments default-route to the same
# inspection (or, without the firewall, egress) attachment, and the tables
# behind it know every spoke, so prod could reach nonprod through the firewall
# or the NAT gateway. A blackhole for each spoke CIDR in the OTHER segment's
# table wins over 0.0.0.0/0 by longest prefix and drops the packet at the
# TGW. Spokes in the same segment still reach each other. Keyed
# "<table>|<spoke>": plan-known.
locals {
  segment_isolation_routes = merge([
    for k, s in var.spoke_attachments : {
      for seg in ["prod", "nonprod"] : "${seg}|${k}" => { route_table = seg, cidr = s.cidr }
      if seg != s.segment
    } if s.cidr != null
  ]...)
}

resource "aws_ec2_transit_gateway_route" "segment_isolation" {
  for_each = local.segment_isolation_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[each.value.route_table]
  blackhole                      = true
}

check "segments_isolated" {
  assert {
    condition = !(
      contains([for s in values(var.spoke_attachments) : s.segment], "prod") &&
      contains([for s in values(var.spoke_attachments) : s.segment], "nonprod")
    ) || alltrue([for s in values(var.spoke_attachments) : s.cidr != null])
    error_message = "prod and nonprod spokes are both attached but some spoke_attachments have no cidr, so their segments can reach each other. Set aws.workload_environments.<env>.vpc_cidr (the root copies it) or spoke_attachments.<key>.cidr."
  }
}
