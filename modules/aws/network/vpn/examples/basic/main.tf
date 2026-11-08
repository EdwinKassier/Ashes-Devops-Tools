# Basic working example for the aws/vpn module.
# Creates a Site-to-Site IPsec VPN from an on-premises device to a Transit
# Gateway, with two redundant tunnels, BGP dynamic routing and the module's
# IKEv2 / AES-GCM-256 defaults. The tunnel pre-shared keys stay in an
# AWS-managed Secrets Manager secret (the default), so they never enter
# Terraform state. Run `terraform init && terraform validate` here to check it.
#
# The customer gateway IP (a documentation address), ASN and Transit Gateway ID
# are placeholders: replace them with your own.

module "vpn" {
  source = "../../"

  name                     = "onprem-dc1"
  customer_gateway_ip      = "203.0.113.10"
  customer_gateway_bgp_asn = 65010

  attach_to          = "transit_gateway"
  transit_gateway_id = "tgw-0123456789abcdef0"

  tags = {
    environment = "network"
  }
}
