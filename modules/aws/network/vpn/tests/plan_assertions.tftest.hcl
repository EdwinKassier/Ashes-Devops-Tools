# Plan assertions for the network/vpn module (mock_provider — no creds).

mock_provider "aws" {}

variables {
  name                = "onprem-dc1"
  customer_gateway_ip = "203.0.113.10"
  transit_gateway_id  = "tgw-0123456789abcdef0"
}

run "tgw_termination_and_secure_defaults" {
  command = plan

  assert {
    condition     = aws_customer_gateway.this.ip_address == "203.0.113.10"
    error_message = "customer gateway must use the supplied on-prem IP"
  }

  assert {
    condition     = aws_customer_gateway.this.type == "ipsec.1"
    error_message = "customer gateway must be ipsec.1"
  }

  assert {
    condition     = aws_vpn_connection.this.transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "VPN must attach to the Transit Gateway when attach_to = transit_gateway"
  }

  assert {
    condition     = aws_vpn_connection.this.vpn_gateway_id == null
    error_message = "VGW must be null when terminating on a Transit Gateway"
  }

  assert {
    condition     = contains(aws_vpn_connection.this.tunnel1_ike_versions, "ikev2")
    error_message = "tunnel 1 must default to IKEv2"
  }

  assert {
    condition     = contains(aws_vpn_connection.this.tunnel1_phase1_encryption_algorithms, "AES256-GCM-16")
    error_message = "tunnel 1 phase-1 must default to AES256-GCM-16"
  }
}

run "vgw_termination" {
  command = plan

  variables {
    attach_to          = "vpn_gateway"
    transit_gateway_id = null
    vpn_gateway_id     = "vgw-0123456789abcdef0"
    static_routes_only = true
    static_routes      = ["10.0.0.0/8"]
  }

  assert {
    condition     = aws_vpn_connection.this.vpn_gateway_id == "vgw-0123456789abcdef0"
    error_message = "VPN must attach to the VGW when attach_to = vpn_gateway"
  }

  assert {
    condition     = length(aws_vpn_connection_route.this) == 1
    error_message = "one static route must be planned for a VGW static-routing VPN"
  }
}
