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
#     (east-west, egress replies, on-premises via the hybrid table) can reach it.
#     prod and nonprod never learn each other's routes directly.
#
# Hub routes the spokes need (spoke_hub_routes in main.tf, only when at least
# one spoke is wired, so an estate without spokes plans no change):
#   - inspection 0.0.0.0/0 -> egress attachment: inspected internet-bound
#     traffic reaches the NAT gateways;
#   - shared top_cidr -> inspection attachment: NAT replies (egress is in the
#     shared segment) go back through the firewall to the spoke, so egress is
#     inspected both ways (the inspection attachment runs in appliance mode).
# ---------------------------------------------------------------------------

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
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids["inspection"]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.spoke]
}
