# AWS Site-to-Site VPN — hybrid connectivity to an on-premises network. The AWS
# parity counterpart to GCP's network/vpn (HA-VPN). Terminates on either a
# Transit Gateway (recommended, centralized) or a Virtual Private Gateway.
# AWS provisions two tunnels per connection for redundancy by default.

resource "aws_customer_gateway" "this" {
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"
  tags       = merge(var.tags, { Name = "${var.name}-cgw" })
}

resource "aws_vpn_connection" "this" {
  customer_gateway_id = aws_customer_gateway.this.id
  type                = "ipsec.1"

  # Terminate on a Transit Gateway OR a Virtual Private Gateway (exactly one).
  transit_gateway_id = var.attach_to == "transit_gateway" ? var.transit_gateway_id : null
  vpn_gateway_id     = var.attach_to == "vpn_gateway" ? var.vpn_gateway_id : null

  static_routes_only = var.static_routes_only
  # Global Accelerator is only valid on a Transit Gateway attachment; the provider
  # rejects the argument (even = false) alongside a VGW, so omit it unless TGW.
  enable_acceleration = var.attach_to == "transit_gateway" ? var.enable_acceleration : null
  tunnel1_inside_cidr = length(var.tunnel_inside_cidrs) == 2 ? var.tunnel_inside_cidrs[0] : null
  tunnel2_inside_cidr = length(var.tunnel_inside_cidrs) == 2 ? var.tunnel_inside_cidrs[1] : null

  # Modern, secure IKE/IPsec defaults on both tunnels: IKEv2 only, strong DH
  # groups and AES-GCM, and rekey/replay hardening.
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel1_phase1_dh_group_numbers      = [19, 20, 21]
  tunnel2_phase1_dh_group_numbers      = [19, 20, 21]
  tunnel1_phase2_dh_group_numbers      = [19, 20, 21]
  tunnel2_phase2_dh_group_numbers      = [19, 20, 21]
  tunnel1_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase2_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase2_encryption_algorithms = ["AES256-GCM-16"]

  tags = merge(var.tags, { Name = "${var.name}-vpn" })
}

# Static routes (only meaningful when static_routes_only = true and terminating
# on a VGW; TGW routing is managed on the TGW route tables).
resource "aws_vpn_connection_route" "this" {
  for_each = var.static_routes_only && var.attach_to == "vpn_gateway" ? toset(var.static_routes) : []

  destination_cidr_block = each.value
  vpn_connection_id      = aws_vpn_connection.this.id
}
